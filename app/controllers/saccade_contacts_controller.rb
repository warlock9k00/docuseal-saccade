# frozen_string_literal: true

# Saccade, 2026-11-27: contact cards (see config/saccade_contacts.rb). /contacts lists everyone who has a card or has
# been sent a document; a card shows the details, where each came from, the documents for that email and the shared
# links to send. Details are edited here by hand; forms update them when signed.
# Modification of DocuSeal 3.3.8 (AGPL-3.0); source: https://github.com/warlock9k00/docuseal-saccade.
class SaccadeContactsController < ApplicationController
  skip_authorization_check
  before_action :load_card, only: %i[show update destroy]

  def index
    cards = SaccadeContacts.all(current_account.id).index_by { |c| c.value['email'] }
    @query = params[:q].to_s.strip.downcase
    @rows = cards.map do |email, c|
      d = SaccadeContacts.data(c)
      { email:, id: c.id, name: d['full_name'], entity: d['entity_name'], status: d['status'],
        updated_at: c.value['updated_at'] }
    end
    @rows.select! { |r| r.values.compact.join(' ').downcase.include?(@query) } if @query.present?
    @rows.sort_by! { |r| r[:updated_at].to_s }.reverse!
    @docs = submitters_scope.where('LOWER(submitters.email) IN (?)', @rows.pluck(:email))
                            .group('LOWER(submitters.email)').count
    @without_card = submitters_scope.where.not(email: [nil, ''])
                                    .where.not('LOWER(submitters.email) IN (?)', cards.keys.presence || [''])
                                    .where.not('LOWER(submitters.email) IN (?)', company_emails.presence || [''])
                                    .group('LOWER(submitters.email)').count
  end

  def create
    email = SaccadeContacts.normalize_email(params[:email])
    unless email&.match?(User::VALIDATE_EMAIL_REGEXP)
      return redirect_to(saccade_contacts_path, alert: 'Enter a valid email.')
    end

    if (existing = SaccadeContacts.find(current_account.id, email))
      return redirect_to(saccade_contact_path(existing.id))
    end

    card = SaccadeContacts.update!(current_account.id, email, {}, source: manual_source)
    redirect_to saccade_contact_path(card.id), notice: 'Card created.'
  end

  def show
    @data = SaccadeContacts.data(@card)
    @sources = @card.value.fetch('sources', {})
    @history = @card.value.fetch('history', [])
    @documents = submitters_scope.where('LOWER(submitters.email) = ?', @card.value['email'])
                                 .includes(submission: :template).order('submitters.id DESC')
    @templates = Template.where(account_id: current_account.id, archived_at: nil, shared_link: true)
                         .includes(:folder).order(:id)
                         .reject { |t| t.folder&.name == SaccadeContacts::TEST_FOLDER }
  end

  def update
    changes = SaccadeContacts::FIELDS.keys.index_with { |k| params.dig(:card, k).to_s }
    SaccadeContacts.update!(current_account.id, @card.value['email'], changes, source: manual_source, allow_blank: true)
    redirect_to saccade_contact_path(@card.id), notice: 'Saved.'
  end

  # Deletes the card only; documents and their data stay in DocuSeal.
  def destroy
    @card.destroy!
    Rails.logger.info("[saccade_contacts] card #{@card.value['email']} deleted by #{current_user.email}")
    redirect_to saccade_contacts_path, notice: 'Card deleted. Documents are not affected.'
  end

  private

  def load_card
    @card = AccountConfig.where(account_id: current_account.id)
                         .where('key LIKE ?', "#{SaccadeContacts::KEY_PREFIX}%").find(params[:id])
  end

  def submitters_scope
    Submitter.where(account_id: current_account.id).joins(:submission).where(submissions: { archived_at: nil })
  end

  def company_emails
    User.where(account_id: current_account.id).pluck(:email).map(&:downcase)
  end

  def manual_source
    { 'by' => 'manual', 'user' => current_user.email }
  end
end
