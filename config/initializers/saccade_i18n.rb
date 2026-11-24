# frozen_string_literal: true

# Saccade: signer pages fully in ONE language (2026-11-24, Sasha: "при английском всё на английском, при русском — на русском").
# DocuSeal 3.3.8 has no Russian at all. This adds:
#  - Rails locale :ru (texts in config/locales/saccade_ru.yml, mounted), fallback :en;
#  - signer controllers (start_form*, submit_form*, submissions_preview) take the language from cookie saccade_lang
#    (the EN/RU switch), else Accept-Language ru -> ru, else English. Admin pages are untouched (account locale, English);
#  - SaccadeI18n.localize_fields: step titles in Russian (FIELD_TITLES_RU, or field key "title_ru") and only the
#    paragraphs of the chosen language in descriptions; used by submit_form/_submission_form.html.erb (override);
#  - the Vue form's own strings (Type here..., Next, Complete, Draw/Type/Upload...) in Russian: VUE_RU in
#    shared/_saccade_lang.html.erb, set as the form's i18n prop after mount.
# New field name in a template -> add it to FIELD_TITLES_RU (or set "title_ru" on the field), otherwise the step title stays
# English in RU mode. Reports of untranslated names: SaccadeI18n.missing_titles.

Rails.application.config.after_initialize do
  I18n.available_locales = (I18n.available_locales + [:ru]).uniq
  # translations of a locale that was not available at load time are dropped by the Simple backend: load them again
  I18n.backend.reload!
end

module SaccadeI18n
  SIGNER_CONTROLLERS = /\A(start_form|submit_form|submissions_preview|submissions_download)/

  FIELD_TITLES_RU = {
    'Full name (as in passport, Latin)' => 'Полное имя (как в паспорте, латиницей)',
    'Status' => 'Статус',
    'Trade name or entity name' => 'Название ИП или компании',
    'Address' => 'Адрес',
    'Address (in Latin letters)' => 'Адрес (латиницей)',
    'Tax ID' => 'Налоговый номер',
    'Tax number (if any)' => 'Налоговый номер (если есть)',
    'Email' => 'Почта',
    'Phone' => 'Телефон',
    'Electronic signature consent' => 'Согласие на электронную подпись',
    'I agree to sign this Agreement electronically' => 'Согласен(на) подписать договор электронно',
    'Signatory full name' => 'Имя подписанта',
    'Capacity, if signing for an entity' => 'Должность, если подписываете за компанию',
    'Recipient signature' => 'Подпись',
    'Recipient date' => 'Дата',
    'Review before sending' => 'Проверка перед отправкой',
    'I have reviewed the signed Agreement and want to send it' => 'Я проверил(а) подписанный договор и хочу его отправить',
    'Agreement No.' => 'Номер договора',
    'Company signature' => 'Подпись компании',
    'Company date' => 'Дата (компания)',
    'Affiliate signature (Sec. 9.7)' => 'Подпись аффилированного лица (п. 9.7)',
    'Affiliate date' => 'Дата (аффилированное лицо)',
    'Hand-signed NDA (scan)' => 'NDA, подписанное от руки (скан)',
    'Hand-signed copy confirmation' => 'Подтверждение подписанной копии',
    'I confirm the uploaded file is this Agreement signed by me' => 'Подтверждаю: загружен этот договор с моей подписью',
    'Agreement date (e.g. 25 November 2026)' => 'Дата договора (например, 25 November 2026)',
    'NDA date (day and month, e.g. 25 November)' => 'Дата NDA (день и месяц, например, 25 November)',
    'Start of your work on GANTZ (indicative)' => 'Начало работы над GANTZ (примерно)',
    'Platform account email' => 'Почта аккаунта на платформе',
    'Platform login' => 'Логин на платформе',
    'City of access in Germany' => 'Город доступа в Германии',
    'City of access in Russia' => 'Город доступа в России',
    'Access to the platform since' => 'Доступ к платформе с',
    'Signature — NDA' => 'Подпись — NDA',
    'Date — NDA' => 'Дата — NDA',
    'Signature — Certificate' => 'Подпись — сертификат',
    'Date — Certificate' => 'Дата — сертификат',
    'Signature — Exhibit D' => 'Подпись — Exhibit D',
    'Date — Exhibit D' => 'Дата — Exhibit D'
  }.freeze

  # "Signature p.10" / "Date p.10" (agreement pages)
  PATTERNS_RU = [
    [/\ASignature p\.\s*(\d+)\z/, 'Подпись, с. \1'],
    [/\ADate p\.\s*(\d+)\z/, 'Дата, с. \1']
  ].freeze

  # radio / select option labels shown to the signer; the stored value stays English (it goes into the English document)
  OPTIONS_RU = {
    'Individual' => 'Физлицо',
    'Sole proprietor' => 'ИП',
    'Entity' => 'Компания'
  }.freeze

  # document names shown to the signer (header, start/completed screens, browser tab); project and brand names stay as they are
  NAMES_RU = {
    'NDA Gantz - Tereshonok Victoria (+ certificate, Exhibit D, Elen)' => 'NDA Gantz — Терешонок Виктория (+ сертификат, Exhibit D, Элен)',
    'Agreement Gantz - Khegai Sofia (SK-01)' => 'Договор Gantz — Хегай София (SK-01)',
    'NDA Accumulator - Lobodin Artem' => 'NDA Accumulator — Лободин Артём',
    'NDA Accumulator - Ionov Aleksei' => 'NDA Accumulator — Ионов Алексей',
    'NDA ALL3 (hand-signed)' => 'NDA ALL3 (подпись от руки)',
    'TEST - ' => 'ТЕСТ — ',
    ' (check 21.11)' => ' (проверка 21.11)'
  }.freeze

  CYR = /[А-Яа-яЁё]/
  LAT = /[A-Za-z]/

  module_function

  def lang_from(cookies, request)
    l = cookies[:saccade_lang].to_s
    return l if %w[en ru].include?(l)

    request.env['HTTP_ACCEPT_LANGUAGE'].to_s =~ /\A\s*ru\b/i ? 'ru' : 'en'
  end

  def title_ru(text)
    return nil if text.blank?
    return FIELD_TITLES_RU[text] if FIELD_TITLES_RU.key?(text)

    PATTERNS_RU.each { |re, sub| return text.sub(re, sub) if text.match?(re) }
    nil
  end

  def doc_name(name, lang)
    return name if lang != 'ru' || name.blank?

    NAMES_RU.keys.sort_by { |k| -k.length }.reduce(name.dup) { |n, k| n.gsub(k, NAMES_RU[k]) }
  end

  def para_lang(text)
    plain = text.to_s.gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')
    plain.match?(CYR) ? 'ru' : (plain.match?(LAT) ? 'en' : nil)
  end

  # keep the paragraphs of one language when the description has both (paragraphs are separated by a blank line)
  def description_for(desc, lang)
    return desc if desc.blank?

    paras = desc.split(/\n\s*\n/)
    langs = paras.map { |p| para_lang(p) }
    return desc unless langs.include?('en') && langs.include?('ru')

    paras.each_with_index.select { |_, i| langs[i].nil? || langs[i] == lang }.map(&:first).join("\n\n")
  end

  def localize_fields(fields, lang)
    fields.map do |f|
      f = f.dup
      f['description'] = description_for(f['description'], lang) if f['description'].present?
      if lang == 'ru'
        ru = f['title_ru'].presence || title_ru(f['title'].presence || f['name'])
        f['title'] = ru if ru
      end
      f
    end
  end

  COMPLETED_TITLES_RU = { 'Thank you!' => 'Спасибо!' }.freeze

  # completion screen of the Vue form: title in the chosen language, body paragraphs of that language only
  def localize_completed(msg, lang)
    msg = msg.to_h.dup
    msg['title'] = COMPLETED_TITLES_RU.fetch(msg['title'], msg['title']) if lang == 'ru' && msg['title'].present?
    msg['body'] = description_for(msg['body'], lang) if msg['body'].present?
    msg
  end

  def missing_titles(fields)
    fields.filter_map { |f| n = f['title'].presence || f['name']; n if n.present? && f['title_ru'].blank? && title_ru(n).nil? }
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
