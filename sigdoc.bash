#!/bin/bash
set -o allexport -o errexit -o privileged -o pipefail -o nounset
shopt -s extglob

# Exports an ODT document to a PDF file.
# Creates a checksum file for the PDF file.
# Creates duplicate checksum files for each signature needed, to be signed.
# Allows signing of each signature file.
# Packages everything into a .tar.xz file.

SIGNATURE_TOKEN_PATTERN="CRYPTOGRAPHIC SIGNATURE TOKEN:"

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
	local odt_filepath pdf_filepath sig_tokens checksum_filepath
	odt_filepath="$1"
	pdf_filepath="$(export_pdf "$odt_filepath")"
	checksum_filepath="${pdf_filepath}.checksum"

	git hash-object "$pdf_filepath" > "$checksum_filepath"

	sig_tokens="$(get_signature_tokens "$odt_filepath")"
	for sig_token in $sig_tokens; do
		local sigsum_filepath="${pdf_filepath}.${sig_token}.checksum"
		cp "$checksum_filepath" "$sigsum_filepath"
		echo "created $sig_token checksum file for signature"
	done	
}

function sign () {
  local odt_filepath pdf_filepath checksum_filepath sig_tokens
	odt_filepath="$1"
	pdf_filepath="$(get_pdf_filepath "$odt_filepath")"
	checksum_filepath="${pdf_filepath}.checksum"
	
	[ -f "$checksum_filepath" ] || {
		echo "error: checksum file does not exist for: $pdf_filepath"
		exit 1
	}

	sig_tokens="$(get_signature_tokens "$odt_filepath")"
	PS3="Select a signature token to sign: "
	select sig_token in $sig_tokens; do
		local sigsum_filepath="${pdf_filepath}.${sig_token}.checksum"
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
  local filepath ext odt_filepath pdf_filepath checksum_filepath checksum sig_tokens
  filepath="$1"
	odt_filepath="$1"
	pdf_filepath="$(get_pdf_filepath "$odt_filepath")"
	checksum_filepath="${pdf_filepath}.checksum"
	
	[ -f "$odt_filepath" ] || {
		echo "error: ODT document does not exist for: $odt_filepath"
		exit 1
	}

	[ -f "$pdf_filepath" ] || {
		echo "error: PDF document does not exist for: $pdf_filepath"
		exit 1
	}

	[ -f "$checksum_filepath" ] || {
		echo "error: checksum file does not exist for: $checksum_filepath"
		exit 1
	}

	checksum="$(git hash-object "$pdf_filepath")"
	[[ "$(cat "$checksum_filepath")" == "$checksum" ]] || {
		echo "invalid checksum"
		exit 1
	}

	sig_tokens="$(get_signature_tokens "$odt_filepath")"
	for sig_token in $sig_tokens; do
		local sigsum_filepath="${pdf_filepath}.${sig_token}.checksum"
		[ -f "$sigsum_filepath" ] || {
			echo "error: signature checksum file does not exist for: $sig_token"
			exit 1
		}

		[[ "$(cat "$sigsum_filepath")" == "$checksum" ]] || {
			echo "invalid checksum for signature file: $sigsum_filepath"
			exit 1
		}

		local sig_filepath="${sigsum_filepath}.gpg"
		[ -f "$sig_filepath" ] || {
			echo "error: signature file does not exist for: $sig_token"
			exit 1
		}

		gpg --verify "$sig_filepath"
		echo "$sig_token is signed"
	done	

	echo "VALID: checksums are valid. all signatures are provided and valid"
}

function package () {
	local odt_filepath pdf_filepath dirpath datestamp zip_filepath sig_tokens
	odt_filepath="$1"
	pdf_filepath="$(get_pdf_filepath "$odt_filepath")"

	verify "$odt_filepath"

	dirpath="$(dirname "$odt_filepath")"
	datestamp="$(datestamp)"
	zip_filepath="$(basename "$odt_filepath" .odt) - Signed ${datestamp}.tar.xz"

	local -a input_idx=0
	local -a input_filepaths
	input_filepaths[input_idx++]="$(basename "$odt_filepath")"
	input_filepaths[input_idx++]="$pdf_filepath"
	input_filepaths[input_idx++]="$pdf_filepath.checksum"

	sig_tokens="$(get_signature_tokens "$odt_filepath")"
	for sig_token in $sig_tokens; do
		local sigsum_filepath="${pdf_filepath}.${sig_token}.checksum"
		input_filepaths[input_idx++]="$sigsum_filepath"
		input_filepaths[input_idx++]="$sigsum_filepath.gpg"
	done

	tar -cJf "$zip_filepath" -C "$dirpath" "${input_filepaths[@]}"

	for ((i = 1; i < input_idx; ++i)); do
		rm "${input_filepaths[$i]}"
	done
}

function get_signature_tokens () {
  local odt_filepath tokens
	odt_filepath="$1"
	tokens="$(odt2txt "$odt_filepath" | grep "$SIGNATURE_TOKEN_PATTERN" | awk '{print $4}')"
	echo "$tokens"
}

function datestamp () {
	date "+%Y-%m-%d"
}

function get_pdf_filepath () {
  local odt_filepath pdf_filepath
	odt_filepath="$1"
	pdf_filepath="$(basename "$odt_filepath" .odt) - Signed $(datestamp).pdf"
	echo "$pdf_filepath"
}

function export_pdf () {
  local odt_filepath export_filepath pdf_filepath
	odt_filepath="$1"

	libreoffice --headless --nologo --convert-to pdf:writer_pdf_Export --print-to-file "$odt_filepath"

	export_filepath="$(basename "$odt_filepath" .odt).pdf"
	pdf_filepath="$(get_pdf_filepath "$odt_filepath")"

	mv "$export_filepath" "$pdf_filepath"
	echo "$pdf_filepath"
}

main "$1" "${2-}"
exit 0
