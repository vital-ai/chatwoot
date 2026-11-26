import wootConstants from 'dashboard/constants/globals';
import wootAPI from './apiClient';

export const getTestimonialContent = () => {
  // Vital's fork: nothing is fetched from Chatwoot's servers on a custom-branded installation
  if (!wootConstants.TESTIMONIAL_URL) return Promise.resolve({ data: [] });
  return wootAPI.get(wootConstants.TESTIMONIAL_URL);
};
