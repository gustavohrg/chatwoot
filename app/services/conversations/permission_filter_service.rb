class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if administrator?
    return conversations.assigned_to(user) if restrict_agents_to_assigned_conversations?

    accessible_conversations
  end

  private

  def accessible_conversations
    conversations.where(inbox: user.inboxes.where(account_id: account.id))
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def administrator?
    user_role == 'administrator'
  end

  def restrict_agents_to_assigned_conversations?
    ChatwootApp.restrict_agents_to_assigned_conversations? && user_role == 'agent' && !custom_role_user?
  end

  def user_role
    account_user&.role
  end

  def custom_role_user?
    account_user&.respond_to?(:custom_role_id) && account_user.custom_role_id.present?
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
