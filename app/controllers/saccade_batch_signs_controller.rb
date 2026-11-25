# frozen_string_literal: true

# Saccade, 2026-11-25: batch signing for the company. One page lists every submission where the signed-in user is the
# last signer still to sign (everyone else has completed). The user ticks the ones to sign, confirms once that they
# have reviewed them, and the saved profile signature is applied to each, exactly as the form does it: the saved
# signature blob is attached to the submitter (as SubmitFormPrefillAttachmentsController does) and
# Submitters::SubmitValues.call completes it, so the audit log gets the usual start_form / complete_form events with
# this request's IP and browser, and ProcessSubmitterCompletionJob sends the completed copies as usual.
# A submission is offered only if the user's fields are: signature (any), checkbox (ticked by the confirmation),
# read-only or defaulted fields (e.g. today's date) and optional fields left empty. Anything else — sign in the form.
# Modification of DocuSeal 3.3.8 (AGPL-3.0); source: https://github.com/warlock9k00/docuseal-saccade.
class SaccadeBatchSignsController < ApplicationController
  skip_authorization_check

  CONFIRMATION = 'I, %<name>s, am authorized to sign on behalf of the company named in each document. ' \
                 'I have reviewed each of the %<docs>s listed above and intend to electronically sign ' \
                 'each of them for the company with my saved signature.'

  def self.confirmation_text(user, count)
    format(CONFIRMATION, name: user.full_name.presence || user.email, docs: count == 1 ? '1 document' : "#{count} documents")
  end

  # "Open" goes through here so the audit data shows which documents were opened before signing.
  def open
    item = pending_items.find { |i| i[:submitter].id == params[:id].to_i }
    raise ActionController::RoutingError, 'Not Found' unless item

    s = item[:submitter]
    s.update_columns(metadata: (s.metadata || {}).merge(
      'saccade_batch_opened_at' => Array(s.metadata&.dig('saccade_batch_opened_at')) + [Time.current.iso8601]
    ))
    redirect_to submission_path(item[:submission])
  end

  def index
    @signature = UserConfigs.load_signature(current_user)
    @items = pending_items
    @results = flash[:saccade_batch_results]
  end

  def create
    signature = UserConfigs.load_signature(current_user)
    return redirect_to(saccade_batch_sign_path, alert: 'Save your signature in Profile first.') unless signature
    unless params[:reviewed] == '1'
      return redirect_to(saccade_batch_sign_path, alert: 'Tick the confirmation that you have reviewed the documents.')
    end

    ids = Array(params[:submitter_ids]).map(&:to_i)
    items = pending_items.select { |i| i[:batchable] && ids.include?(i[:submitter].id) }
    return redirect_to(saccade_batch_sign_path, alert: 'Nothing selected.') if items.empty?

    batch = { 'batch_id' => SecureRandom.uuid, 'batch_size' => items.size,
              'confirmation' => self.class.confirmation_text(current_user, items.size) }
    results = items.map { |item| sign!(item, signature, batch) }

    flash[:saccade_batch_results] = results
    redirect_to saccade_batch_sign_path
  end

  private

  def pending_items
    Submitter.where(account_id: current_account.id, completed_at: nil, declined_at: nil)
             .where('LOWER(submitters.email) = ?', current_user.email.downcase)
             .joins(:submission).where(submissions: { archived_at: nil })
             .includes(submission: %i[template submitters])
             .order('submitters.id DESC')
             .filter_map { |s| build_item(s) }
  end

  def build_item(submitter)
    submission = submitter.submission
    return if submission.template&.archived_at? || submission.expired?

    others = submission.submitters.reject { |s| s.id == submitter.id }
    return if others.empty? || others.any? { |s| s.completed_at.nil? }

    Submissions.update_template_fields!(submission) if submission.template_fields.blank?
    fields = submission.template_fields.select { |f| f['submitter_uuid'] == submitter.uuid }
    blocker = fields.find { |f| !batchable_field?(f) }

    { submitter:, submission:, fields:, others:, batchable: blocker.nil?, blocker: blocker&.dig('name') }
  end

  # SHA-256 of the PDF the user reviewed: the last signed result of the other signers.
  def reviewed_pdf_sha256(others)
    doc = others.flat_map { |o| o.documents_attachments.to_a }.max_by(&:created_at)
    doc && Digest::SHA256.hexdigest(doc.download)
  rescue StandardError
    nil
  end

  def batchable_field?(field)
    return true if field['type'].in?(%w[signature checkbox])
    return true if field['readonly'] == true || field['default_value'].present?

    field['required'] != true
  end

  def sign!(item, signature, batch)
    submitter = item[:submitter]
    fields = item[:fields]
    submitter.reload
    return { 'id' => submitter.submission_id, 'ok' => false, 'error' => 'already signed' } if submitter.completed_at?

    values = {}
    fields.each do |f|
      case f['type']
      when 'signature'
        values[f['uuid']] = submitter.attachments_attachments.find_or_create_by!(blob_id: signature.blob_id).uuid
      when 'checkbox'
        values[f['uuid']] = true unless f['readonly'] == true
      end
    end

    submit_params = ActionController::Parameters.new('values' => values, 'completed' => 'true')
    submitter.metadata = (submitter.metadata || {}).merge('saccade_batch_signed_at' => Time.current.iso8601)
    audit = batch.merge('document' => item[:submission].template&.name.to_s,
                        'counterparty' => item[:others].map { |o| [o.name.presence, o.email].compact.join(' ') },
                        'reviewed_pdf_sha256' => reviewed_pdf_sha256(item[:others]),
                        'opened_at' => Array(submitter.metadata&.dig('saccade_batch_opened_at')))
    Submitters::SubmitValues.call(submitter, submit_params, request)

    if (event = SubmissionEvent.where(submitter_id: submitter.id, event_type: 'complete_form').order(:id).last)
      event.update_columns(data: (event.data || {}).merge('saccade_batch' => audit))
    end

    { 'id' => submitter.submission_id, 'ok' => true }
  rescue StandardError => e
    Rails.logger.error("[saccade_batch_sign] submitter #{submitter.id}: #{e.class}: #{e.message}")
    { 'id' => submitter.submission_id, 'ok' => false, 'error' => e.message.to_s.truncate(120) }
  end
end
