# Webhook Signature Implementation Plan for Bot Webhooks

## Overview
This plan outlines the implementation of webhook signatures for bot webhook calls in Chatwoot to enable verification of webhook origin and prevent unauthorized webhook spoofing.

## Current State Analysis

### Existing Webhook Flow
1. **Event Trigger**: `AgentBotListener` captures events (message_created, conversation_opened, etc.)
2. **Job Queue**: `AgentBots::WebhookJob` queues webhook delivery
3. **HTTP Delivery**: `Webhooks::Trigger` sends POST request to `agent_bot.outgoing_url`
4. **Current Headers**: Only `content_type: :json, accept: :json`

### Integration Points
- **Primary**: `lib/webhooks/trigger.rb` - HTTP request execution
- **Environment**: Global webhook secret via `CHATWOOT_BOT_WEBHOOK_SECRET` environment variable
- **Configuration**: No database changes required

## Signature Design

### Algorithm Choice: HMAC-SHA256
- **Standard**: Widely adopted by GitHub, Stripe, Shopify
- **Security**: Cryptographically secure with shared secret
- **Performance**: Fast computation, minimal overhead

### Header Format
```
X-Chatwoot-Signature: sha256=<hex_encoded_hmac>
```

### Signature Generation
```ruby
# Pseudocode
timestamp = Time.current.to_i
payload_body = request_payload.to_json
signature_payload = "#{timestamp}.#{payload_body}"
signature = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, signature_payload)
header_value = "sha256=#{signature}"
```

### Additional Security Headers
```
X-Chatwoot-Timestamp: <unix_timestamp>
X-Chatwoot-Bot-Id: <agent_bot_id>
```

## Environment Configuration

### Global Webhook Secret
```bash
# Environment variable for global bot webhook signing
CHATWOOT_BOT_WEBHOOK_SECRET=your_base64_encoded_secret_here
```

### Secret Management Strategy
- **Global Secret**: Single shared secret for all bot webhooks
- **Format**: Base64-encoded 32-byte random value
- **Storage**: Environment variable or AWS Secrets Manager
- **Rotation**: Update environment variable across all instances
- **Generation**: `openssl rand -base64 32`

## Implementation Plan

### Phase 1: Core Infrastructure
1. **Environment Configuration**
   - Add `CHATWOOT_BOT_WEBHOOK_SECRET` to environment variables
   - Update deployment configurations (Docker, ECS, etc.)
   - Document secret generation process

2. **Signature Service**
   - Create `Webhooks::SignatureService` class
   - Implement HMAC-SHA256 signature generation using global secret
   - Add timestamp-based replay protection
   - Add environment variable validation

### Phase 2: Webhook Delivery Integration
1. **Update Webhook Trigger**
   - Modify `lib/webhooks/trigger.rb`
   - Add signature headers to HTTP requests
   - Maintain backward compatibility

2. **Error Handling**
   - Handle missing webhook secrets gracefully
   - Log signature generation failures
   - Maintain existing error handling flow

### Phase 3: Documentation Updates
1. **Documentation Updates**
   - Update bot webhook documentation with signature verification
   - Add environment variable configuration guide
   - Update deployment documentation

### Phase 4: Documentation & Testing
1. **Developer Documentation**
   - Signature verification examples
   - Security best practices
   - Troubleshooting guide

2. **Testing**
   - Unit tests for signature generation
   - Integration tests for webhook delivery
   - Security testing for replay attacks

## Code Changes Required

### 1. Environment Configuration
```bash
# .env or environment variables
CHATWOOT_BOT_WEBHOOK_SECRET=your_base64_encoded_secret_here

# Generate a new secret:
# openssl rand -base64 32
```

```ruby
# config/application.rb or initializer
class Application < Rails::Application
  config.chatwoot_bot_webhook_secret = ENV['CHATWOOT_BOT_WEBHOOK_SECRET']
end
```

### 2. Signature Service (`lib/webhooks/signature_service.rb`)
```ruby
class Webhooks::SignatureService
  class << self
    def generate(payload, timestamp = nil)
      return nil unless webhook_secret_configured?
      
      timestamp ||= Time.current.to_i
      signature_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, signature_payload)
      "sha256=#{signature}"
    end
    
    def verify(payload, signature, timestamp, tolerance = 300)
      return false unless webhook_secret_configured?
      
      expected_signature = generate(payload, timestamp)
      return false unless secure_compare(signature, expected_signature)
      return false if timestamp_expired?(timestamp, tolerance)
      true
    end
    
    def enabled?
      webhook_secret_configured?
    end
    
    private
    
    def webhook_secret
      Rails.application.config.chatwoot_bot_webhook_secret
    end
    
    def webhook_secret_configured?
      webhook_secret.present?
    end
    
    def secure_compare(a, b)
      ActiveSupport::SecurityUtils.secure_compare(a, b)
    end
    
    def timestamp_expired?(timestamp, tolerance)
      Time.current.to_i - timestamp.to_i > tolerance
    end
  end
end
```

### 3. Updated Webhook Trigger (`lib/webhooks/trigger.rb`)
```ruby
def perform_request
  timestamp = Time.current.to_i
  signature = generate_signature(timestamp) if bot_webhook_with_signatures?
  
  headers = { content_type: :json, accept: :json }
  headers.merge!(signature_headers(signature, timestamp)) if signature
  
  RestClient::Request.execute(
    method: :post,
    url: @url,
    payload: @payload.to_json,
    headers: headers,
    timeout: 5
  )
end

private

def bot_webhook_with_signatures?
  bot_webhook? && Webhooks::SignatureService.enabled?
end

def bot_webhook?
  # Check if this is an agent bot webhook (you may need to adjust this logic)
  # based on how you identify bot webhooks in your current system
  @payload[:bot].present? || @webhook_type.to_s.include?('bot')
end

def generate_signature(timestamp)
  return nil unless bot_webhook_with_signatures?
  
  Webhooks::SignatureService.generate(@payload.to_json, timestamp)
end

def signature_headers(signature, timestamp)
  return {} unless signature
  
  headers = {
    'X-Chatwoot-Signature' => signature,
    'X-Chatwoot-Timestamp' => timestamp.to_s
  }
  
  # Add bot ID if available in payload
  if @payload[:bot]&.dig(:id)
    headers['X-Chatwoot-Bot-Id'] = @payload[:bot][:id].to_s
  end
  
  headers
end
```

## Security Considerations

### Replay Attack Prevention
- Include timestamp in signature payload
- Reject requests older than 5 minutes (configurable)
- Bot systems should validate timestamp freshness

### Secret Management
- Single global secret shared across all bot webhooks
- Stored as environment variable or in secrets management system
- Rotation requires updating environment across all instances
- Never log or expose secrets in responses
- Consider using different secrets per environment (dev/staging/prod)

### Backward Compatibility
- Signature headers are additive (won't break existing bots)
- Bots can opt-in to signature verification
- Gradual migration path for existing integrations

## Verification Examples for Bot Developers

### Node.js Example
```javascript
const crypto = require('crypto');

// Your bot's webhook secret (same as CHATWOOT_BOT_WEBHOOK_SECRET)
const WEBHOOK_SECRET = process.env.CHATWOOT_BOT_WEBHOOK_SECRET;

function verifyWebhook(payload, signature, timestamp, tolerance = 300) {
  // Check timestamp freshness
  if (Math.floor(Date.now() / 1000) - parseInt(timestamp) > tolerance) {
    return false;
  }
  
  const expectedSignature = crypto
    .createHmac('sha256', WEBHOOK_SECRET)
    .update(`${timestamp}.${payload}`)
    .digest('hex');
    
  const receivedSignature = signature.replace('sha256=', '');
  
  return crypto.timingSafeEqual(
    Buffer.from(expectedSignature, 'hex'),
    Buffer.from(receivedSignature, 'hex')
  );
}

// Express.js middleware example
app.use('/webhook', (req, res, next) => {
  const signature = req.headers['x-chatwoot-signature'];
  const timestamp = req.headers['x-chatwoot-timestamp'];
  const payload = JSON.stringify(req.body);
  
  if (!verifyWebhook(payload, signature, timestamp)) {
    return res.status(401).send('Unauthorized');
  }
  
  next();
});
```

### Python Example
```python
import hmac
import hashlib
import time
import os
from flask import Flask, request, abort

# Your bot's webhook secret (same as CHATWOOT_BOT_WEBHOOK_SECRET)
WEBHOOK_SECRET = os.environ.get('CHATWOOT_BOT_WEBHOOK_SECRET')

def verify_webhook(payload, signature, timestamp, tolerance=300):
    if not WEBHOOK_SECRET:
        return False
        
    if time.time() - int(timestamp) > tolerance:
        return False
        
    expected_signature = hmac.new(
        WEBHOOK_SECRET.encode(),
        f"{timestamp}.{payload}".encode(),
        hashlib.sha256
    ).hexdigest()
    
    received_signature = signature.replace('sha256=', '')
    return hmac.compare_digest(expected_signature, received_signature)

# Flask example
app = Flask(__name__)

@app.route('/webhook', methods=['POST'])
def handle_webhook():
    signature = request.headers.get('X-Chatwoot-Signature')
    timestamp = request.headers.get('X-Chatwoot-Timestamp')
    payload = request.get_data(as_text=True)
    
    if not verify_webhook(payload, signature, timestamp):
        abort(401)
    
    # Process webhook...
    return 'OK'
```

## Implementation Status

### ✅ Phase 1: Core Infrastructure (COMPLETED)
- ✅ Environment variable configuration (`CHATWOOT_BOT_WEBHOOK_SECRET`)
- ✅ Signature service implementation (`lib/webhooks/signature_service.rb`)
- ✅ Rails configuration (`config/initializers/chatwoot_bot_webhook.rb`)
- ✅ Deployment configuration updates (AWS, local)

### ✅ Phase 2: Webhook Delivery Integration (COMPLETED)
- ✅ Webhook trigger updates (`lib/webhooks/trigger.rb`)
- ✅ Agent bot job modifications (`app/jobs/agent_bots/webhook_job.rb`)
- ✅ Bot payload enhancement (`app/listeners/agent_bot_listener.rb`)
- ✅ Error handling and logging
- ✅ Comprehensive test suite (`spec/lib/webhooks/signature_service_spec.rb`)

### 🔄 Phase 3: Testing & Validation (IN PROGRESS)
- ✅ Unit tests for signature service
- 🔄 Local testing environment setup
- ⏳ Integration testing with real bot webhooks
- ⏳ Documentation updates

### ⏳ Phase 4: Production Rollout (PENDING)
- ⏳ Gradual feature rollout
- ⏳ Monitor webhook delivery success rates
- ⏳ Gather feedback from bot developers

## Migration Strategy

### Phase 1: Infrastructure (Week 1) - ✅ COMPLETED
- Environment variable configuration
- Signature service implementation
- Deployment configuration updates

### Phase 2: Integration (Week 2) - ✅ COMPLETED
- Webhook delivery updates
- Testing and validation
- Error handling

### Phase 3: Testing & Documentation (Week 3) - 🔄 IN PROGRESS
- Local testing setup
- Integration testing
- Documentation updates
- Developer guides and examples

### Phase 4: Rollout (Week 4) - ⏳ PENDING
- Production deployment
- Monitor webhook delivery success rates
- Gather feedback from bot developers

## Success Metrics

### Technical Metrics
- Webhook delivery success rate maintained (>99%)
- Signature generation performance (<1ms overhead)
- Zero security incidents related to webhook spoofing

### Adoption Metrics
- Percentage of bots using signature verification
- Developer feedback scores
- Support ticket reduction for webhook security issues

## Risks & Mitigation

### Risk: Breaking Existing Integrations
**Mitigation**: Additive-only changes, comprehensive testing, gradual rollout

### Risk: Performance Impact
**Mitigation**: Efficient HMAC implementation, performance monitoring, caching where appropriate

### Risk: Secret Compromise
**Mitigation**: Environment variable rotation process, monitoring for unusual patterns, security best practices documentation, consider per-environment secrets

## Local Testing Environment

### Prerequisites
- Docker & Docker Compose installed
- Local PostgreSQL database running
- Chatwoot local development environment set up

### Environment Setup

1. **Configure webhook secret in `.env.local`**:
   ```bash
   # Bot webhook signature secret (already configured)
   CHATWOOT_BOT_WEBHOOK_SECRET=your_base64_encoded_secret_here
   ```

2. **Start local services**:
   ```bash
   cd deploy_local
   ./start.sh
   ```

3. **Access services**:
   - Chatwoot Web: http://localhost:3000
   - Sidekiq Web UI: http://localhost:7433
   - MinIO Console: http://localhost:9001
   - Redis: localhost:6379

### Testing Webhook Signatures

#### 1. Create Test Bot

```bash
# Access Rails console
cd deploy_local
docker-compose exec chatwoot-web bundle exec rails console
```

```ruby
# Create test account and bot
account = Account.create!(name: "Test Account")
bot = AgentBot.create!(
  account: account,
  name: "Test Bot",
  outgoing_url: "https://webhook.site/your-unique-url"
)

# Create inbox and connect bot
inbox = Inbox.create!(
  account: account,
  name: "Test Inbox",
  channel_type: "Channel::WebWidget"
)

AgentBotInbox.create!(
  agent_bot: bot,
  inbox: inbox,
  status: "active"
)
```

#### 2. Set Up Webhook Receiver

Use [webhook.site](https://webhook.site) or create a simple test server:

```javascript
// test-webhook-server.js
const express = require('express');
const crypto = require('crypto');
const app = express();

app.use(express.raw({ type: 'application/json' }));

const WEBHOOK_SECRET = 'your_base64_encoded_secret_here';

function verifyWebhook(payload, signature, timestamp, tolerance = 300) {
  if (Math.floor(Date.now() / 1000) - parseInt(timestamp) > tolerance) {
    return false;
  }
  
  const expectedSignature = crypto
    .createHmac('sha256', WEBHOOK_SECRET)
    .update(`${timestamp}.${payload}`)
    .digest('hex');
    
  const receivedSignature = signature.replace('sha256=', '');
  
  return crypto.timingSafeEqual(
    Buffer.from(expectedSignature, 'hex'),
    Buffer.from(receivedSignature, 'hex')
  );
}

app.post('/webhook', (req, res) => {
  const signature = req.headers['x-chatwoot-signature'];
  const timestamp = req.headers['x-chatwoot-timestamp'];
  const botId = req.headers['x-chatwoot-bot-id'];
  const payload = req.body.toString();
  
  console.log('Received webhook:');
  console.log('- Signature:', signature);
  console.log('- Timestamp:', timestamp);
  console.log('- Bot ID:', botId);
  console.log('- Payload:', payload);
  
  if (verifyWebhook(payload, signature, timestamp)) {
    console.log('✅ Signature verified successfully!');
    res.status(200).send('OK');
  } else {
    console.log('❌ Signature verification failed!');
    res.status(401).send('Unauthorized');
  }
});

app.listen(3001, () => {
  console.log('Test webhook server running on http://localhost:3001/webhook');
});
```

#### 3. Trigger Test Webhooks

```ruby
# In Rails console, create test message to trigger webhook
conversation = Conversation.create!(
  account: account,
  inbox: inbox,
  contact: Contact.create!(account: account, name: "Test Contact")
)

message = Message.create!(
  account: account,
  inbox: inbox,
  conversation: conversation,
  message_type: "incoming",
  content: "Test message to trigger bot webhook"
)
```

#### 4. Verify Signature Headers

Check your webhook receiver logs for:
- `X-Chatwoot-Signature: sha256=<hmac>`
- `X-Chatwoot-Timestamp: <unix_timestamp>`
- `X-Chatwoot-Bot-Id: <agent_bot_id>`

### Testing Commands

```bash
# Check if signatures are enabled
docker-compose exec chatwoot-web bundle exec rails runner \
  "puts Webhooks::SignatureService.enabled? ? 'Enabled' : 'Disabled'"

# Test signature generation
docker-compose exec chatwoot-web bundle exec rails runner \
  "puts Webhooks::SignatureService.generate('{\"test\": \"payload\"}', 1634567890)"

# View webhook job queue
docker-compose exec chatwoot-web bundle exec rails runner \
  "puts Sidekiq::Queue.new('high').size"

# Monitor webhook delivery logs
docker-compose logs -f chatwoot-web | grep -i webhook
```

### Debugging Webhook Issues

1. **Check environment variable**:
   ```bash
   docker-compose exec chatwoot-web printenv | grep CHATWOOT_BOT_WEBHOOK_SECRET
   ```

2. **Verify bot configuration**:
   ```ruby
   bot = AgentBot.find(1)
   puts "Bot URL: #{bot.outgoing_url}"
   puts "Bot webhook data: #{bot.webhook_data}"
   ```

3. **Test signature service directly**:
   ```ruby
   payload = '{"test": "data"}'
   timestamp = Time.current.to_i
   signature = Webhooks::SignatureService.generate(payload, timestamp)
   puts "Generated signature: #{signature}"
   
   # Verify it
   verified = Webhooks::SignatureService.verify(payload, signature, timestamp)
   puts "Verification result: #{verified}"
   ```

## Future Enhancements

### Advanced Features
- Multiple signature algorithms support
- Webhook retry with exponential backoff
- Webhook delivery analytics and monitoring
- Rate limiting per bot
- Webhook payload encryption for sensitive data

### Integration Improvements
- SDK libraries for popular languages
- Webhook testing tools in dashboard
- Real-time webhook delivery status
- Webhook event filtering and routing

### Testing Tools
- Built-in webhook signature validator
- Webhook delivery simulator
- Signature verification examples for more languages
- Integration with popular webhook testing services