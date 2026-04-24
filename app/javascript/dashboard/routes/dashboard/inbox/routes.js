import { frontendURL } from 'dashboard/helper/URLHelper';
import InboxListView from './InboxList.vue';
import InboxDetailView from './InboxView.vue';
import InboxEmptyStateView from './InboxEmptyState.vue';
import { CONVERSATION_PERMISSIONS } from 'dashboard/constants/permissions.js';

const ADMIN_AND_CONVERSATION_PERMISSIONS = [
  'administrator',
  ...CONVERSATION_PERMISSIONS,
];

export const routes = [
  {
    path: frontendURL('accounts/:accountId/inbox-view'),
    component: InboxListView,
    children: [
      {
        path: '',
        name: 'inbox_view',
        component: InboxEmptyStateView,
        meta: {
          permissions: ADMIN_AND_CONVERSATION_PERMISSIONS,
        },
      },
      {
        path: ':type/:id',
        name: 'inbox_view_conversation',
        component: InboxDetailView,
        meta: {
          permissions: ADMIN_AND_CONVERSATION_PERMISSIONS,
        },
      },
    ],
  },
];
