## @defgroup on-ssl SSL-Werkzeuge
## @brief Erzeugung und Verwaltung von Schlüsseln, Zertifikaten und Zertifikatsanfragen
# Beginn der Doku-Gruppe
## @{

if [ -x "/usr/bin/openssl" ]; then
	SSL_LIBRARY=openssl
elif [ -x "/usr/bin/gen_key" ]; then
	SSL_LIBRARY=mbedtls
elif [ -x "/usr/bin/certtool" ]; then
	SSL_LIBRARY=gnutls
else
	SSL_LIBRARY=
fi

get_ssl_certificate_cn() {
	local filename="$1"
	case "$SSL_LIBRARY" in
		openssl)
			openssl x509 -in "$filename" -subject -nameopt multiline -noout \
				| awk '/commonName/ {print $3}'
			;;
		gnutls)
			get_ssl_certificate_subject_components "$filename" | sed -n 's/^CN //p'
			;;
		*)
			msg_info "'get_ssl_certificate_cn': missing implementation for SSL library ('$SSL_LIBRARY')"
			;;
	esac
}


_filter_multiline_openssl_subject_output() {
	sed '/^subject=/d; s/^ *//; s/=/ /'
}


# input: admin@opennet-initiative.de,CN=2.210.aps.on,OU=users,O=Opennet Initiative e.V. / F23,ST=Mecklenburg-Vorpommern,C=de
# output:
#    C de
#    ST Mecklenburg-Vorpommern
#    O Opennet Initiative e.V. / F23
#    OU users
#    CN 2.210.aps.on
#    admin@opennet-initiative.de
_filter_gnutls_subject_output() {
	# split into lines, separate by space, reverse order of lines
	tr ',' '\n' | tr '=' ' ' | sed -n '1!G;h;$p'
}


# return the components of a certificate's subject
# Each resulting line starts with the name of the component followed by a space and the value.
# Example:
#   countryName de
#   stateOrProvinceName Mecklenburg-Vorpommern
#   organizationName Foo Bar
#   organizationalUnitName users
#   commonName 1.23.aps.on
#   emailAddress foo@example.org
get_ssl_certificate_subject_components() {
	local filename="$1"
	[ -e "$filename" ] || return 0
	case "$SSL_LIBRARY" in
		openssl)
			openssl x509 -nameopt sep_multiline,lname -subject -noout | _filter_multiline_openssl_subject_output
			;;
		gnutls)
			certtool --certificate-info | sed -n 's/^\s*Subject: *\(.*\)$/\1/p' | _filter_gnutls_subject_output
			;;
		*)
			msg_info "'get_ssl_certificate_subject_components': missing implementation for SSL library ('$SSL_LIBRARY')"
			;;
	esac <"$filename"
}


# see "get_ssl_certificate_subject_components" for the output format
get_ssl_csr_subject_components() {
	local filename="$1"
	[ -e "$filename" ] || return 0
	case "$SSL_LIBRARY" in
		openssl)
			openssl req -nameopt sep_multiline,lname -subject -noout | _filter_multiline_openssl_subject_output
			;;
		gnutls)
			certtool --crq-info | sed -n 's/^\s*Subject: *\(.*\)$/\1/p' | _filter_gnutls_subject_output
			;;
		*)
			msg_info "'get_ssl_csr_subject_components': missing implementation for SSL library ('$SSL_LIBRARY')"
			;;
	esac <"$filename"
}


get_ssl_certificate_enddate() {
	local filename="$1"
	[ -e "$filename" ] || return 0
	case "$SSL_LIBRARY" in
		openssl)
			openssl x509 -enddate -noout | cut -f 2- -d "="
			;;
		gnutls)
			certtool --certificate-info | sed -n 's/^\s*Not After: *\(.*\)$/\1/p'
			;;
		*)
			msg_info "'get_ssl_certificate_enddate': missing implementation for SSL library ('$SSL_LIBRARY')"
			;;
	esac <"$filename"
}


get_ssl_object_hash() {
	local filename="$1"
	local object_type="$2"
	[ -e "$filename" ] || return 0
	case "$SSL_LIBRARY" in
		openssl)
			case "$object_type" in
				rsa|req|x509)
					openssl "$object_type" -noout -modulus | cut -f 2- -d "=" | md5sum
					;;
				*)
					msg_info "Requested invalid object type hash: '$object_type' (should be one of: rsa / req / x509)"
					;;
			esac
			;;
		gnutls)
			case "$object_type" in
				rsa)
					certtool --key-info \
						| sed '1,/^modulus:$/d; /^$/,$d; s/^\s*//'
					;;
				req)
					certtool --crq-info \
						| sed 's/^\s*//; 1,/^Modulus/d; /^Exponent/,$d'
					;;
				x509)
					certtool --certificate-info \
						| sed 's/^\s*//; 1,/^Modulus/d; /^Exponent/,$d'
					;;
			esac | tr -d ':\n' | sed 's/^0*//' | tr 'a-z' 'A-Z'
			;;
		*)
			msg_info "'get_ssl_object_hash': missing implementation for SSL library ('$SSL_LIBRARY')"
			;;
	esac <"$filename"
}


generate_ssl_key() {
	local filename="$1"
	local num_bits="${2:-2048}"
	local tmp_filename
	tmp_filename=$(mktemp)
	case "$SSL_LIBRARY" in
		openssl)
			openssl genrsa -out "$tmp_filename" "$num_bits"
			;;
		mbedtls)
			gen_key type=rsa rsa_keysize="$num_bits" filename="$tmp_filename"
			;;
		*)
			msg_info "'generate_ssl_key': missing implementation for SSL library ('$SSL_LIBRARY')"
			;;
	esac
	mv "$tmp_filename" "$filename"
}


generate_ssl_certificate_request() {
	local filename="$1"
	local existing_key_filename="$2"
	local attribute_country="$3"
	local attribute_province="$4"
	local attribute_locality="$5"
	local attribute_organizational_unit="$6"
	local attribute_organization_name="$7"
	local attribute_cn="$8"
	local attribute_email="$9"
	local duration_days="$10"
	local tmp_filename
	tmp_filename=$(mktemp)
	if [ -e "$existing_key_filename" ]; then
		msg_info "Failed to create certificate request due to missing key file: $existing_key_filename"
		trap "" EXIT && return 1
	else
		case "$SSL_LIBRARY" in
			openssl)
				openssl_countryName="$attribute_country" \
					openssl_provinceName="$attribute_province" \
					openssl_localityName="$attribute_locality" \
					openssl_organizationalUnitName="$attribute_organizational_unit" \
					openssl_organizationName="$attribute_organization_name" \
					openssl_commonName="$attribute_cn" \
					openssl_EmailAddress="$attribute_email" \
					openssl req -config /etc/ssl/on_openssl.cnf -batch -nodes -new \
						-days "$duration_days" \
						-key "$existing_key_filename" \
						-out "$tmp_filename"
				;;
			mbedtls)
				cert_req filename="$existing_key_filename" \
					output_file="$tmp_filename" \
					subject_name="$attribute_cn"
				;;
			*)
				msg_info "Requested invalid SSL library: '$SSL_LIBRARY' (maybe missing?)"
				;;
		esac
	fi
	mv "$tmp_filename" "$filename"
}

# Ende der Doku-Gruppe
## @}
