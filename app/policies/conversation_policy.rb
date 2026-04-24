class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  def show?
    administrator? || agent_bot? || agent_can_view_conversation?
  end

  private

  def agent_can_view_conversation?
    return assigned_to_user? if restrict_agents_to_assigned_conversations?

    inbox_access? || team_access?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?

    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    record.conversation_participants.exists?(user_id: user.id)
  end

  def restrict_agents_to_assigned_conversations?
    ChatwootApp.restrict_agents_to_assigned_conversations? && account_user&.agent? && !custom_role_user?
  end

  def custom_role_user?
    account_user&.respond_to?(:custom_role_id) && account_user.custom_role_id.present?
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
