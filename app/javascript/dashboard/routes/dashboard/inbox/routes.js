import { frontendURL } from 'dashboard/helper/URLHelper';
import InboxListView from './InboxList.vue';
import InboxDetailView from './InboxView.vue';
import InboxEmptyStateView from './InboxEmptyState.vue';
const INBOX_VIEW_PERMISSIONS = ['administrator'];

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
          permissions: INBOX_VIEW_PERMISSIONS,
        },
      },
      {
        path: ':type/:id',
        name: 'inbox_view_conversation',
        component: InboxDetailView,
        meta: {
          permissions: INBOX_VIEW_PERMISSIONS,
        },
      },
    ],
  },
];
