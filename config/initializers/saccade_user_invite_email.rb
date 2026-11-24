# frozen_string_literal: true

# Saccade, 2026-11-24: subject of the e-mail inviting a team member: "You are invited to Saccade Legal" instead of
# "You are invited to DocuSeal". Brand name from SACCADE_MAIL_FROM_NAME (as in the sender name); unset: DocuSeal's subject.
# The body is in app/views/user_mailer/invitation_email.html.erb. The DocuSeal attribution on the signing screens stays.
# Modification of DocuSeal 3.3.8 (AGPL-3.0); source: https://github.com/warlock9k00/docuseal-saccade.
Rails.application.config.after_initialize do
  brand = ENV['SACCADE_MAIL_FROM_NAME'].to_s.delete('"').strip

  unless brand.empty?
    UserMailer.prepend(Module.new do
      define_method(:invitation_email) do |*args, **kwargs|
        result = super(*args, **kwargs)
        message.subject = "You are invited to #{brand}"
        result
      end
    end)
  end
end
