# frozen_string_literal: true

# Saccade, 2026-11-27: contact card. One card per signer email keeps their details (name, status, entity, address,
# tax ID, phone, bank details). The card is
#   - filled from every signed form: fields whose names are in FIELDS below (the same names in all our NDAs);
#   - edited by hand on /contacts (app/controllers/saccade_contacts_controller.rb);
#   - used to prefill the signer's form when they open it: only fields that are empty, editable and named in FIELDS,
#     once per signer, and only when the form was reached by an emailed link or a shared link with the email code
#     (template preference shared_link_2fa). The signer sees the values and can change them; what they sign updates
#     the card.
# Stored in account_configs (key "saccade_contact:<email>", JSON), no new tables. Company signers (users of the
# account) get no card. Test templates (folder "TEST audit") give cards only to @example.com addresses.
# Modification of DocuSeal 3.3.8 (AGPL-3.0); source: https://github.com/warlock9k00/docuseal-saccade.
module SaccadeContacts
  KEY_PREFIX = 'saccade_contact:'
  TEST_FOLDER = 'TEST audit'
  HISTORY_LIMIT = 100

  # card key => [label on /contacts, field names in templates (first is the canonical one for new templates)]
  FIELDS = {
    'full_name' => ['Full name (as in passport, Latin)', ['Full name (as in passport, Latin)']],
    'status' => ['Status', ['Status']],
    'entity_name' => ['Trade name or entity name', ['Trade name or entity name']],
    'address' => ['Address', ['Address', 'Address (in Latin letters)']],
    'tax_id' => ['Tax ID', ['Tax ID', 'Tax number (if any)']],
    'phone' => ['Phone', ['Phone']],
    'signatory_name' => ['Signatory full name', ['Signatory full name']],
    'capacity' => ['Capacity, if signing for an entity', ['Capacity, if signing for an entity']],
    'bank_holder' => ['Bank account holder', ['Bank account holder']],
    'bank_name' => ['Bank name', ['Bank name']],
    'bank_account' => ['IBAN or account number', ['IBAN or account number']],
    'bank_swift' => ['SWIFT / BIC', ['SWIFT / BIC']],
    'bank_address' => ['Bank address', ['Bank address']],
    'notes' => ['Notes (not used in forms)', []]
  }.freeze
  FILL_TYPES = %w[text radio select phone].freeze

  module_function

  def normalize_email(email)
    email.to_s.strip.downcase.presence
  end

  def key_for(email)
    "#{KEY_PREFIX}#{normalize_email(email)}"
  end

  def field_key(field_name)
    name = field_name.to_s.strip
    return 'email' if name == 'Email'

    FIELDS.find { |_, (_, names)| names.include?(name) }&.first
  end

  def find(account_id, email)
    return if normalize_email(email).blank?

    AccountConfig.find_by(account_id:, key: key_for(email))
  end

  def all(account_id)
    AccountConfig.where(account_id:).where('key LIKE ?', "#{KEY_PREFIX}%").to_a
  end

  def data(config)
    (config&.value || {}).fetch('data', {})
  end

  def company_email?(account_id, email)
    User.where(account_id:).where('LOWER(email) = ?', normalize_email(email)).exists?
  end

  # Writes changes into the card (creates it if needed). changes: {key => value}; blank values are ignored, so a field
  # left empty in a form never erases what the card already has. Manual edits pass allow_blank: true.
  def update!(account_id, email, changes, source:, allow_blank: false)
    email = normalize_email(email)
    return unless email

    config = AccountConfig.find_or_initialize_by(account_id:, key: key_for(email))
    value = config.value.is_a?(Hash) ? config.value.deep_dup : {}
    value['email'] = email
    value['data'] ||= {}
    value['sources'] ||= {}
    value['history'] ||= []
    value['created_at'] ||= Time.current.iso8601

    diff = {}
    changes.each do |k, v|
      next unless FIELDS.key?(k)

      v = v.to_s.strip
      next if v.blank? && !allow_blank
      next if value['data'][k].to_s == v

      diff[k] = [value['data'][k], v.presence]
      v.present? ? value['data'][k] = v : value['data'].delete(k)
      value['sources'][k] = source.merge('at' => Time.current.iso8601)
    end
    return config if diff.empty? && config.persisted?

    value['history'] = ([source.merge('at' => Time.current.iso8601, 'changes' => diff)] + value['history'])
                       .first(HISTORY_LIMIT)
    value['updated_at'] = Time.current.iso8601
    config.value = value
    config.save!
    config
  end

  def submitter_fields(submitter)
    fields = submitter.submission.template_fields.presence || submitter.submission.template&.fields || []
    fields.select { |f| f['submitter_uuid'] == submitter.uuid }
  end

  def test_template?(template)
    template&.folder&.name == TEST_FOLDER
  end

  def card_allowed?(submitter)
    email = normalize_email(submitter.email)
    return false unless email
    return false if company_email?(submitter.account_id, email)
    return email.end_with?('@example.com') if test_template?(submitter.submission.template)

    true
  end

  # After a signer completes: copy the named fields they filled into their card.
  def capture!(submitter)
    return unless submitter.completed_at? && card_allowed?(submitter)

    changes = {}
    submitter_fields(submitter).each do |f|
      key = field_key(f['name'])
      next if key.nil? || key == 'email'

      v = submitter.values[f['uuid']]
      changes[key] = v if v.is_a?(String) && v.strip.present?
    end
    return if changes.empty?

    update!(submitter.account_id, submitter.email, changes,
            source: { 'by' => 'form', 'submission_id' => submitter.submission_id,
                      'template' => submitter.submission.template&.name.to_s })
  rescue StandardError => e
    Rails.logger.error("[saccade_contacts] capture submitter #{submitter&.id}: #{e.class}: #{e.message}")
    nil
  end

  def prefill_allowed?(submitter)
    submission = submitter.submission
    return false if submitter.completed_at? || submitter.declined_at? || submission.completed_at?
    return false if submitter.metadata&.dig('saccade_contact_prefilled_at').present?
    return false unless card_allowed?(submitter)
    return true unless submission.source.to_s == 'link'

    submission.template&.preferences&.dig('shared_link_2fa') == true
  end

  # Before the signer's form is shown the first time: fill empty, editable named fields from the card.
  def prefill!(submitter)
    return unless prefill_allowed?(submitter)

    card = data(find(submitter.account_id, submitter.email))
    card = card.merge('email' => normalize_email(submitter.email))
    values = submitter.values.dup
    filled = []

    submitter_fields(submitter).each do |f|
      next unless FILL_TYPES.include?(f['type'])
      next if f['readonly'] == true || f['default_value'].present? || values[f['uuid']].present?

      key = field_key(f['name'])
      v = key && card[key]
      next if v.blank?

      if f['type'].in?(%w[radio select])
        next unless Array(f['options']).any? { |o| o['value'].to_s == v }
      end

      values[f['uuid']] = v
      filled << f['name']
    end

    meta = (submitter.metadata || {}).merge('saccade_contact_prefilled_at' => Time.current.iso8601,
                                            'saccade_contact_prefilled' => filled)
    submitter.update_columns(values:, metadata: meta)
  rescue StandardError => e
    Rails.logger.error("[saccade_contacts] prefill submitter #{submitter&.id}: #{e.class}: #{e.message}")
    nil
  end
end

Rails.application.config.after_initialize do
  Submitters::SubmitValues.singleton_class.prepend(Module.new do
    define_method(:call) do |submitter, *args, **kwargs|
      result = super(submitter, *args, **kwargs)
      SaccadeContacts.capture!(submitter) if submitter.completed_at?
      result
    end
  end)

  SubmitFormController.class_eval do
    before_action :saccade_contact_prefill, only: :show

    private

    def saccade_contact_prefill
      return unless @submitter
      return unless Submitters::AuthorizedForForm.pass_email_2fa?(@submitter, request)

      SaccadeContacts.prefill!(@submitter)
    end
  end
end

Rails.application.routes.prepend do
  get 'contacts', to: 'saccade_contacts#index', as: :saccade_contacts
  post 'contacts', to: 'saccade_contacts#create'
  get 'contacts/:id', to: 'saccade_contacts#show', as: :saccade_contact
  patch 'contacts/:id', to: 'saccade_contacts#update'
  delete 'contacts/:id', to: 'saccade_contacts#destroy'
end
