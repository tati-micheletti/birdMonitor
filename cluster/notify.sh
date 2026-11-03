#!/bin/bash
# Sends a short e-mail from the cluster. NOTIFY_EMAIL = one or more addresses (comma or space separated).
#   NOTIFY_EMAIL="a@ufz.de,b@ufz.de" bash cluster/notify.sh "subject" /path/to/body.txt
# Tries mail, mailx and sendmail in this order. Exit code 0 = handed to a mail program, 1 = not sent (the caller should not fail because of that).
subject="${1:?usage: notify.sh <subject> <body file>}"; body="${2:?usage: notify.sh <subject> <body file>}"
to="${NOTIFY_EMAIL:-}"
[ -n "${to}" ] || { echo "notify: NOTIFY_EMAIL is not set, no e-mail sent" >&2; exit 1; }
to=$(echo "${to}" | tr ',' ' ')
for prog in mail mailx; do
  if command -v "${prog}" >/dev/null 2>&1 && "${prog}" -s "${subject}" ${to} < "${body}"; then echo "notify: sent with ${prog} to ${to}"; exit 0; fi
done
if command -v sendmail >/dev/null 2>&1; then
  if { echo "To: ${to// /, }"; echo "Subject: ${subject}"; echo; cat "${body}"; } | sendmail -t; then echo "notify: sent with sendmail to ${to}"; exit 0; fi
fi
echo "notify: no mail program worked (tried mail, mailx, sendmail); the text is in ${body}" >&2
exit 1
