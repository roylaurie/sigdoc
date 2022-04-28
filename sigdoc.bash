#!/bin/bash

SIGNATURE_TOKEN_PATTERN="CRYPTOGRAPHIC SIGNATURE FILE:"

function main () {
	local action="$1"
	local params="${2-}"

	case "$action" in
		create)
			create "$params"
			;;
		sign)
			sign "$params"
			;;
		verify)
			verify "$params"
			;;
		package)
			package "$params"
			;;
		*)
			echo "usage: $0 {create|sign|verify|package}"
			exit 1 
	esac
}

function create () {
	local filepath="$1"
	local checksum_filepath="${1}.checksum"

	git hash-object "$filepath" > "$checksum_filepath"

	local sig_tokens="$(get_signature_tokens "$filepath")"
	for sig_token in $sig_tokens; do
		local sigsum_filepath="${filepath}.${sig_token}.checksum"
		cp "$checksum_filepath" "$sigsum_filepath"
		echo "created $sig_token checksum file for signature"
	done	
}

function sign () {
	local filepath="$1"
	local checksum_filepath="${filepath}.checksum"
	
	[ -f "$checksum_filepath" ] || {
		echo "error: checksum file does not exist for: $filepath"
		exit 1
	}

	local sig_tokens="$(get_signature_tokens "$filepath")"
	PS3="Select a signature token to sign: "
	select sig_token in $sig_tokens; do
		local sigsum_filepath="${filepath}.${sig_token}.checksum"
		[ -f "$sigsum_filepath" ] || {
			echo "error: signature checksum file does not exist: $sigsum_filepath"
			exit 1
		}

		echo "signing $sigsum_filepath ..."
		gpg --sign "$sigsum_filepath"
		break
	done
}

function verify () {
	local filepath="$1"
	local checksum_filepath="${filepath}.checksum"
	
	[ -f "$filepath" ] || {
		echo "error: document does not exist for: $filepath"
		exit 1
	}

	[ -f "$checksum_filepath" ] || {
		echo "error: checksum file does not exist for: $filepath"
		exit 1
	}

	local checksum="$(git hash-object "$filepath")"
	[[ "$(cat "$checksum_filepath")" == "$checksum" ]] || {
		echo "invalid checksum"
		exit 1
	}

	local sig_tokens="$(get_signature_tokens "$filepath")"
	for sig_token in $sig_tokens; do
		local sigsum_filepath="${filepath}.${sig_token}.checksum"
		[ -f "$sigsum_filepath" ] || {
			echo "error: signature checksum file does not exist for: $sig_token"
			exit 1
		}

		[[ "$(cat "$sigsum_filepath")" == "$checksum" ]] || {
			echo "invalid checksum"
			exit 1
		}

		local sig_filepath="${sigsum_filepath}.gpg"
		[ -f "$sig_filepath" ] || {
			echo "error: signature file does not exist for: $sig_token"
			exit 1
		}

		gpg --verify "$sig_filepath" || exit 1
		echo "$sig_token is signed"
	done	

	echo "VALID: checksums are valid. all signatures are provided and valid"
}

function package () {
	local filepath="$1"

	verify "$filepath"

	local pdf_filepath="$(export_pdf $filepath)"

	local dirpath="$(dirname "$filepath")"
	local datestamp="$(datestamp)"
	local zip_filepath="$(basename "$filepath" .odt) - Signed ${datestamp}.tar.xz"

	local -a input_idx=0
	local -a input_filepaths
	input_filepaths[input_idx++]="$filepath"
	input_filepaths[input_idx++]="$pdf_filepath"
	input_filepaths[input_idx++]="$filepath.checksum"

	local sig_tokens="$(get_signature_tokens "$filepath")"
	for sig_token in $sig_tokens; do
		local sigsum_filepath="${filepath}.${sig_token}.checksum"
		input_filepaths[input_idx++]="$sigsum_filepath"
		input_filepaths[input_idx++]="$sigsum_filepath.gpg"
	done	


	tar -cJf "$zip_filepath" -C "$dirpath" "${input_filepaths[@]}"

	for ((i = 2; i < input_idx; ++i)); do
		rm "${input_filepaths[$i]}"
	done

	
}

function get_signature_tokens () {
	local filepath="$1"
	local tokens="$(odt2txt "$filepath" | grep "$SIGNATURE_TOKEN_PATTERN" | awk '{print $4}')"
	echo $tokens
}

function datestamp () {
	echo "$(date "+%Y-%m-%d")"
}

function export_pdf () {
	local filepath="$1"

	libreoffice --headless --nologo --convert-to pdf:writer_pdf_Export --print-to-file "$filepath"

	local export_filepath="$(basename "$filepath" .odt).pdf"
	local pdf_filepath="$(basename "$filepath" .odt) - Signed $(datestamp).pdf"

	mv "$export_filepath" "$pdf_filepath"
	echo "$pdf_filepath"
}

main "$1" "${2-}"
exit 0
