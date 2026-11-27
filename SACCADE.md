# Saccade modifications to DocuSeal

This branch (`saccade`) is the complete source code of the DocuSeal instance Saccade uses to sign documents. It is DocuSeal **3.3.8** (tag `3.3.8`, Docker image `docuseal/docuseal:3.3.8`) with the changes listed below. It is published to meet section 13 of the GNU Affero General Public License v3.0.

## Changes against 3.3.8

| File | Change |
|---|---|
| `app/views/start_form/_docuseal_logo.html.erb` | The large DocuSeal logo is replaced by a compact header: Saccade logo, a divider, a small DocuSeal logo. On the e-mail code screens: a visible "new code sent" line, a 45 s pause on "Re-send Code", and `autocomplete="one-time-code"` on the code field. |
| `app/views/submit_form/_docuseal_logo.html.erb` | The same header on the signing form, plus a list of fields to fill; step dots coloured by what is filled; on the last step a warning while required fields are empty; the step window never taller than the screen. |
| `app/views/shared/_mailer_attribution.html.erb` | E-mails are sent without the "Sent using ... DocuSeal" footer. The additional terms require the attribution only in interactive user interfaces; the signing screens keep it. |
| `config/initializers/saccade_mail_from_name.rb` | The sender name in e-mails comes from `SACCADE_MAIL_FROM_NAME` instead of the account name. The account name stays everywhere else. |
| `config/initializers/saccade_contacts.rb`, `app/controllers/saccade_contacts_controller.rb`, `app/views/saccade_contacts/*` | Contact cards (`/contacts`): one card per signer email in `account_configs`, filled from signed forms and by hand; empty fields of a new form are prefilled from the card when the signer opens it (emailed link or shared link with the email code only). |

The table lists the main changes; the full list is `git diff 3.3.8 saccade --stat`. In production these files are mounted read-only into the official `docuseal/docuseal:3.3.8` image, see `saccade/run.example.sh`.

Diff: `git diff 3.3.8 saccade -- app/`

## License

DocuSeal and these changes are licensed under AGPL-3.0, see `LICENSE` and `LICENSE_ADDITIONAL_TERMS`. The DocuSeal attribution ("Powered by DocuSeal" and the DocuSeal logo) is kept as those terms require.

The Saccade logo inside these files is a trademark of its owner. It is not licensed under the AGPL and may not be reused.
