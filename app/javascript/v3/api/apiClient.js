import axios from 'axios';

const { apiHost = '' } = window.chatwootConfig || {};
const wootAPI = axios.create({ 
  baseURL: `${apiHost}/`,
  headers: {
    'X-Requested-With': 'XMLHttpRequest'
  }
});

export default wootAPI;
