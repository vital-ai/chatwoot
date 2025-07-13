import { createRouter, createWebHistory } from 'vue-router';

import routes from './routes';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { validateRouteAccess } from '../helpers/RouteHelper';

export const router = createRouter({ history: createWebHistory(), routes });

const sensitiveRouteNames = ['auth_password_edit'];

export const initalizeRouter = () => {
  router.beforeEach((to, from, next) => {
    // Debug logging for route navigation
    console.log('[Router] Navigating to:', { 
      path: to.path, 
      query: to.query, 
      name: to.name, 
      fullPath: to.fullPath,
      from: from.fullPath
    });

    if (!sensitiveRouteNames.includes(to.name)) {
      AnalyticsHelper.page(to.name || '', {
        path: to.path,
        name: to.name,
      });
    }

    return validateRouteAccess(to, next, window.chatwootConfig);
  });
};

export default router;
