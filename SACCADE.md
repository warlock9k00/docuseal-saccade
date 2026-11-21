# Saccade modifications to DocuSeal

This branch (`saccade`) is the complete source code of the DocuSeal instance Saccade uses to sign documents. It is DocuSeal **3.3.8** (tag `3.3.8`, Docker image `docuseal/docuseal:3.3.8`) with the changes listed below. It is published to meet section 13 of the GNU Affero General Public License v3.0.

## Changes against 3.3.8

| File | Change |
|---|---|
| `app/views/start_form/_docuseal_logo.html.erb` | The large DocuSeal logo is replaced by a compact header: Saccade logo, a divider, a small DocuSeal logo. |
| `app/views/submit_form/_docuseal_logo.html.erb` | The same header on the signing form. |

Nothing else is changed. In production the two files are mounted read-only into the official `docuseal/docuseal:3.3.8` image.

Diff: `git diff 3.3.8 saccade -- app/`

## License

DocuSeal and these changes are licensed under AGPL-3.0, see `LICENSE` and `LICENSE_ADDITIONAL_TERMS`. The DocuSeal attribution ("Powered by DocuSeal" and the DocuSeal logo) is kept as those terms require.

The Saccade logo inside the two files is a trademark of its owner. It is not licensed under the AGPL and may not be reused.
