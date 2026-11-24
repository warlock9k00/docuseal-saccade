# frozen_string_literal: true

# Saccade: signer pages fully in ONE language (2026-11-24, Sasha: "при английском всё на английском, при русском — на русском").
# DocuSeal 3.3.8 has no Russian at all. This adds:
#  - Rails locale :ru (texts in config/locales/saccade_ru.yml, mounted), fallback :en;
#  - signer controllers (start_form*, submit_form*, submissions_preview) take the language from cookie saccade_lang
#    (the EN/RU switch), else Accept-Language ru -> ru, else English. Admin pages are untouched (account locale, English);
#  - ALL texts of the signing form (step hints, Russian step titles, option labels, document names, completion screen)
#    come from ONE file, config/saccade_texts.yml, re-read when it changes (no restart). The texts stored in the
#    templates are only a fallback for fields the file does not know. Used by submit_form/_submission_form.html.erb
#    and shared/_saccade_lang.html.erb;
#  - the Vue form's own strings (Type here..., Next, Complete, Draw/Type/Upload...) in Russian: VUE_RU in
#    shared/_saccade_lang.html.erb, set as the form's i18n prop after mount.
# Check: SaccadeI18n.audit (run by `docs/infra/ds texts`).

Rails.application.config.after_initialize do
  I18n.available_locales = (I18n.available_locales + [:ru]).uniq
  # translations of a locale that was not available at load time are dropped by the Simple backend: load them again
  I18n.backend.reload!
end

module SaccadeI18n
  SIGNER_CONTROLLERS = /\A(start_form|submit_form|submissions_preview|submissions_download)/
  TEXTS_PATH = Rails.root.join('config/saccade_texts.yml').to_s
  CYR = /[А-Яа-яЁё]/
  LAT = /[A-Za-z]/
  # Latin words allowed inside Russian text (proper names, document labels)
  LATIN_OK = /Saccade|Media|House|Inc|GANTZ|Gantz|NDA|Exhibit|ALL3|Accumulator|Puma|Hetzner|Google|Spacemail|DocuSeal|PDF|IP|SK-01|Recipient|Latin|\b[A-D]\b|legal@\S+|https?:\/\/\S+|\]\([^)]*\)/

  module_function

  # ---- texts file (cached by mtime) ----
  def texts
    m = File.mtime(TEXTS_PATH)
    return @texts if @texts && @texts_mtime == m

    data = YAML.safe_load_file(TEXTS_PATH, permitted_classes: [], aliases: false) || {}
    data['templates'] = (data['templates'] || {}).transform_keys(&:to_i)
    @texts_mtime = m
    @texts = data
  rescue Errno::ENOENT, Psych::Exception => e
    Rails.logger.error("[saccade_texts] #{e.class}: #{e.message}") # fail loud in the log, keep the templates' own texts
    @texts || { 'fields' => {}, 'templates' => {} }
  end

  def options_ru = texts['options_ru'] || {}

  # template name -> Russian name, plus generic parts (test copies)
  def names_ru
    (texts['templates'] || {}).values.each_with_object({}) { |t, h| h[t['name']] = t['name_ru'] if t['name'] && t['name_ru'] }
                              .merge(texts['name_parts_ru'] || {})
  end

  def lang_from(cookies, request)
    l = cookies[:saccade_lang].to_s
    return l if %w[en ru].include?(l)

    request.env['HTTP_ACCEPT_LANGUAGE'].to_s =~ /\A\s*ru\b/i ? 'ru' : 'en'
  end

  def title_ru(text)
    return nil if text.blank?

    t = texts.dig('fields', text, 'title_ru')
    return t if t.present?

    (texts['title_patterns_ru'] || {}).each { |re, sub| r = Regexp.new(re); return text.sub(r, sub) if text.match?(r) }
    nil
  end

  def doc_name(name, lang)
    return name if lang != 'ru' || name.blank?

    map = names_ru
    map.keys.sort_by { |k| -k.length }.reduce(name.dup) { |n, k| n.gsub(k, map[k]) }
  end

  def para_lang(text)
    plain = text.to_s.gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')
    plain.match?(CYR) ? 'ru' : (plain.match?(LAT) ? 'en' : nil)
  end

  # legacy: a stored description with both languages -> the paragraphs of one language
  def description_for(desc, lang)
    return desc if desc.blank?

    paras = desc.split(/\n\s*\n/)
    langs = paras.map { |p| para_lang(p) }
    return desc unless langs.include?('en') && langs.include?('ru')

    paras.each_with_index.select { |_, i| langs[i].nil? || langs[i] == lang }.map(&:first).join("\n\n")
  end

  # entry of the texts file for this field (template override first); :none = the file does not know the field
  def hint_entry(name, template_id)
    over = texts.dig('templates', template_id, 'fields')
    return over[name] || {} if over.is_a?(Hash) && over.key?(name)

    texts.dig('fields', name) || :none
  end

  def pick(h, lang)
    return nil unless h.is_a?(Hash)

    h[lang].presence || h['en'].presence || h['ru'].presence
  end

  def localize_fields(fields, lang, template_id = nil)
    fields.map do |f|
      f = f.dup
      e = hint_entry(f['name'], template_id)
      if e == :none || !e.key?('hint')
        f['description'] = description_for(f['description'], lang) if f['description'].present?
      else
        f['description'] = pick(e['hint'], lang).to_s
      end
      if lang == 'ru'
        ru = f['title_ru'].presence || title_ru(f['title'].presence || f['name'])
        f['title'] = ru if ru
      end
      f
    end
  end

  # completion screen of the Vue form
  def localize_completed(msg, lang, template_id = nil)
    msg = msg.to_h.dup
    c = texts['completed'] || {}
    body = texts.dig('templates', template_id, 'completed_body') || c['body']
    msg['title'] = pick(c['title'], lang) || msg['title'] if c['title']
    msg['body'] = body ? pick(body, lang) : description_for(msg['body'], lang)
    msg
  end

  def missing_titles(fields)
    fields.filter_map { |f| n = f['title'].presence || f['name']; n if n.present? && f['title_ru'].blank? && title_ru(n).nil? }
  end

  # problems for `ds texts`: unknown fields, missing translations, Latin inside Russian text
  def audit
    out = []
    t = texts
    tpls = Template.where(archived_at: nil).where.not(folder_id: TemplateFolder.where(name: 'TEST audit').select(:id))
    tpls.each do |tpl|
      tpl.fields.each do |f|
        out << "шаблон #{tpl.id}: поле «#{f['name']}» — нет в saccade_texts.yml" unless t['fields']&.key?(f['name'])
        missing_titles([f]).each { |n| out << "шаблон #{tpl.id}: нет title_ru для «#{n}»" }
      end
      out << "шаблон #{tpl.id} «#{tpl.name}»: нет в templates" unless t['templates']&.key?(tpl.id)
    end
    check = lambda do |where, h|
      next unless h.is_a?(Hash)

      out << "#{where}: нет en" if h['en'].blank?
      out << "#{where}: нет ru" if h['ru'].blank?
      rest = h['ru'].to_s.gsub(LATIN_OK, '')
      out << "#{where}: латиница в русском — #{rest.scan(/[A-Za-z][A-Za-z.\-]+/).uniq.first(5).join(', ')}" if rest.match?(/[A-Za-z]{2,}/)
      out << "#{where}: кириллица в английском" if h['en'].to_s.match?(CYR)
    end
    (t['fields'] || {}).each { |n, e| check.("поле «#{n}»", e && e['hint']) }
    (t['templates'] || {}).each do |id, e|
      (e['fields'] || {}).each { |n, x| check.("шаблон #{id}, поле «#{n}»", x && x['hint']) }
      check.("шаблон #{id}, экран после подписи", e['completed_body'])
    end
    check.('экран после подписи', t.dig('completed', 'body'))
    out
  end
end

module SaccadeSignerLocale
  private

  def with_browser_locale(&)
    return super unless controller_path.match?(SaccadeI18n::SIGNER_CONTROLLERS)

    if SaccadeI18n.lang_from(cookies, request) == 'ru'
      I18n.with_locale(:ru, &)
    else
      accept = request.env['HTTP_ACCEPT_LANGUAGE'].to_s
      I18n.with_locale(accept =~ /\A\s*en-US\b/i ? :'en-US' : :'en-GB', &)
    end
  end
end

Rails.application.config.to_prepare do
  ApplicationController.prepend(SaccadeSignerLocale) unless ApplicationController.ancestors.include?(SaccadeSignerLocale)
end
