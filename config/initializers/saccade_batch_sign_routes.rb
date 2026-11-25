# frozen_string_literal: true

# Saccade, 2026-11-25: route for the company batch signing page (app/controllers/saccade_batch_signs_controller.rb).
# Modification of DocuSeal 3.3.8 (AGPL-3.0); source: https://github.com/warlock9k00/docuseal-saccade.
Rails.application.routes.prepend do
  get 'to-sign', to: 'saccade_batch_signs#index', as: :saccade_batch_sign
  post 'to-sign', to: 'saccade_batch_signs#create'
  get 'to-sign/open/:id', to: 'saccade_batch_signs#open'
end
