## @defgroup certificates Opennet-Zertifikate
## @brief x509-Zertifikate für verschiedene Zwecke
# Beginn der certificate-Doku-Gruppe
## @{


ON_CERT_BUNDLE_PATH="/etc/ssl/certs/opennet-initiative.de/opennet-server_bundle.pem"


## @fn https_request_opennet_or_public()
## @brief Rufe den Inhalt ab, auf den eine URL verweist.
## @param URL die Quell-Adresse
## @returns Exitcode=0 falls kein Fehler auftrat. Andernfalls: curl-Exitcodes
## @details Sowohl Opennet-Zertifikaten als auch öffentlichen Zertifikaten (durch OpenWrt gepflegt)
##     wird vertraut.
https_request_opennet_or_public() {
	curl -sS --fail -q --silent --location --max-time 30 --retry 2 \
		--capath /etc/ssl/certs/ --cacert "$ON_CERT_BUNDLE_PATH" "$@"
}


## @fn submit_csr_via_http()
## @param upload_url URL des Upload-Formulars
## @param csr_file Dateiname einer Zertifikatsanfrage
## @brief Einreichung einer Zertifikatsanfrage via http (bei https://ca.opennet-initiative.de)
## @details Eine Prüfung des Ergebniswerts ist aufgrund des auf menschliche Nutzer ausgerichteten Interface nicht so leicht moeglich.
## @todo Umstellung vom Formular auf die zu entwickelnde API
## @returns Das Ergebnis ist die html-Ausgabe des Upload-Formulars.
submit_csr_via_http() {
	trap 'error_trap submit_csr_via_http "$*"' EXIT
	# upload_url: z.B. https://ca.opennet-initiative.de/csr/csr_upload.php
	local upload_url="$1"
	local csr_file="$2"
	local helper="${3:-}"
	local helper_email="${4:-}"
	https_request_opennet_or_public \
		--form "file=@$csr_file" \
		--form "opt_name=$helper" \
		--form "opt_mail=$helper_email" "$upload_url" && return 0
	msg_error "Failed to submit CSR to '$upload_url' via curl ($?)"
	# ein technischer Verbindungsfehler trat auf
	trap "" EXIT && return 1
}

# Ende der certificate-Doku-Gruppe
## @}
