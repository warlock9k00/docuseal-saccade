# frozen_string_literal: true

# Saccade, 2026-11-21: the signing screens have an EN/RU switch (submit_form/_docuseal_logo, start_form/_docuseal_logo).
# It keeps the choice in the cookie saccade_lang. Every submission event DocuSeal records with request data
# (view_form, start_form, email_verified, complete_form, decline_form …) also gets lang: "en" or "ru", so the log shows
# in which language the signer saw the privacy notice and the consent when they gave it. No cookie or another value:
# nothing is added and DocuSeal behaves as before.
# Modification of DocuSeal 3.3.8 (AGPL-3.0); source: https://github.com/warlock9k00/docuseal-saccade.
Rails.application.config.after_initialize do
  SubmissionEvents.singleton_class.prepend(Module.new do
    define_method(:create_with_tracking_data) do |submitter, event_type, request, data = {}|
      lang = request.respond_to?(:cookies) ? request.cookies['saccade_lang'].to_s : ''
      data = data.merge(lang: lang) if %w[en ru].include?(lang) && !data.key?(:lang)
      super(submitter, event_type, request, data)
    end
  end)
end
