# frozen_string_literal: true

# Saccade, 2026-11-21: e-mail with the sign-in code. DocuSeal sends it with the subject "Email verification" and the
# code in small bold text; Gmail took it for a personal letter and showed no "Copy code". Here the code goes first in
# the subject ("123456 is your Saccade Legal verification code", the common pattern for one-time codes) and the
# message is marked as automated (Auto-Submitted: auto-generated, RFC 3834). The body is in
# app/views/shared/_saccade_otp_email.html.erb. Brand name from SACCADE_MAIL_FROM_NAME; unset: no brand in the subject.
# Applies to both code e-mails: shared link (TemplateMailer) and personal link (SubmitterMailer).
# Modification of DocuSeal 3.3.8 (AGPL-3.0); source: https://github.com/warlock9k00/docuseal-saccade.
Rails.application.config.after_initialize do
  brand = ENV['SACCADE_MAIL_FROM_NAME'].to_s.delete('"').strip

  otp_mail = Module.new do
    define_method(:otp_verification_email) do |*args, **kwargs|
      result = super(*args, **kwargs)
      code = @otp_code.to_s
      if code.present?
        message.subject = brand.empty? ? "#{code} is your verification code" : "#{code} is your #{brand} verification code"
        message['Auto-Submitted'] = 'auto-generated'
      end
      result
    end
  end

  [SubmitterMailer, TemplateMailer].each { |mailer| mailer.prepend(otp_mail) }
end
