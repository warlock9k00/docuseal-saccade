# frozen_string_literal: true

# Saccade, 2026-11-21: sender name in e-mails. DocuSeal puts the account name into From
# (lib/action_mailer_configs_interceptor.rb); the account name also shows on the signing screens
# and in e-mail texts, where the legal entity name stays. This changes only the From display name,
# taken from SACCADE_MAIL_FROM_NAME. Variable unset or empty: DocuSeal behaves as before.
# Modification of DocuSeal 3.3.8 (AGPL-3.0); source: https://github.com/warlock9k00/docuseal-saccade.
Rails.application.config.after_initialize do
  name = ENV['SACCADE_MAIL_FROM_NAME'].to_s.delete('"').strip
  next if name.empty?

  ActionMailerConfigsInterceptor.singleton_class.prepend(Module.new do
    define_method(:delivering_email) do |message|
      super(message)
      address = Array(message.from).first
      message.from = %("#{name}" <#{address}>) if address.present?
      message
    end
  end)
end
