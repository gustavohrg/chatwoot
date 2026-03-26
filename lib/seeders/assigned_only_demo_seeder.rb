class Seeders::AssignedOnlyDemoSeeder
  PASSWORD = 'Password1!.'.freeze
  AGENT_A_EMAIL = 'agent.a@assigned-only.demo.test'.freeze
  AGENT_B_EMAIL = 'agent.b@assigned-only.demo.test'.freeze

  def initialize(account:)
    raise 'Account Seeding is not allowed.' unless ENV.fetch('ENABLE_ACCOUNT_SEEDING', !Rails.env.production?)

    @account = account
  end

  def perform!
    reset_account!

    agent_a = ensure_user(name: 'Agent A', email: AGENT_A_EMAIL, role: :agent)
    agent_b = ensure_user(name: 'Agent B', email: AGENT_B_EMAIL, role: :agent)
    inbox = create_inbox!

    InboxMember.find_or_create_by!(user: agent_a, inbox: inbox)
    InboxMember.find_or_create_by!(user: agent_b, inbox: inbox)

    create_conversation!(
      inbox: inbox,
      assignee: agent_a,
      name: 'Contact For Agent A',
      email: 'contact.agent.a@assigned-only.demo.test',
      source_id: 'assigned-only-agent-a',
      incoming_message: 'Need help with invoice A. This should only appear for Agent A.',
      outgoing_message: 'Agent A picked this up.'
    )

    create_conversation!(
      inbox: inbox,
      assignee: agent_b,
      name: 'Contact For Agent B',
      email: 'contact.agent.b@assigned-only.demo.test',
      source_id: 'assigned-only-agent-b',
      incoming_message: 'Need help with invoice B. This should only appear for Agent B.',
      outgoing_message: 'Agent B picked this up.'
    )

    create_conversation!(
      inbox: inbox,
      assignee: nil,
      name: 'Unassigned Contact',
      email: 'contact.unassigned@assigned-only.demo.test',
      source_id: 'assigned-only-unassigned',
      incoming_message: 'This conversation must stay unassigned and hidden from agents.',
      outgoing_message: nil
    )
  end

  private

  attr_reader :account

  def reset_account!
    primary_admin = account.administrators.order(:id).first
    raise 'No administrator found for account.' unless primary_admin

    account.custom_filters.destroy_all
    account.canned_responses.destroy_all
    account.labels.destroy_all
    account.teams.destroy_all
    account.conversations.destroy_all
    account.inboxes.destroy_all
    account.contacts.destroy_all
    account.custom_roles.destroy_all if account.respond_to?(:custom_roles)
    account.account_users.where.not(user_id: primary_admin.id).destroy_all
  end

  def ensure_user(name:, email:, role:)
    user = User.find_or_initialize_by(email: email)
    user.name = name
    user.password = PASSWORD
    user.password_confirmation = PASSWORD
    user.skip_confirmation!
    user.save!

    account_user = AccountUser.find_or_initialize_by(account: account, user: user)
    account_user.role = role
    account_user.save!

    user
  end

  def create_inbox!
    channel = Channel::WebWidget.create!(
      account: account,
      website_url: 'https://assigned-only.demo.test',
      welcome_title: 'Assigned Only Demo',
      welcome_tagline: 'Minimal inbox for assigned-only validation'
    )

    Inbox.create!(
      channel: channel,
      account: account,
      name: 'Assigned Only Demo Inbox'
    )
  end

  def create_conversation!(inbox:, assignee:, name:, email:, source_id:, incoming_message:, outgoing_message:)
    contact = account.contacts.create!(name: name, email: email)
    contact_inbox = inbox.contact_inboxes.create_or_find_by!(contact: contact, source_id: source_id)
    conversation = contact_inbox.conversations.create!(
      account: account,
      contact: contact,
      inbox: inbox,
      assignee: assignee
    )

    conversation.messages.create!(
      account: account,
      sender: contact,
      inbox: inbox,
      content: incoming_message,
      message_type: :incoming
    )

    return conversation if outgoing_message.blank? || assignee.blank?

    conversation.messages.create!(
      account: account,
      sender: assignee,
      inbox: inbox,
      content: outgoing_message,
      message_type: :outgoing
    )

    conversation
  end
end
