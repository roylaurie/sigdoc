# SigDoc
Allows users to review, sign, verify, and package Open Document (ODT) files.

## Usage
sigdoc **action** ...

In the ODT file to be signed, place the following term on the signature line:
CRYPTOGRAPHICALLY SIGNED CHECKSUM: *signature-token-name*

Where **signature-token-name** is a simple monicker for the signature needed, like "finance-mycompany" or "bob-smith".

SigDoc will identify any signature-tokens in an ODT.

Actions:
* create *filename*
* sign *filename*
* verify *filename*
* package *filename*

### create
Creates a checksum file for the document. Creates checksum files for each signature required in the document.

### sign
Provides a list of signature-tokens required within the document and then uses GPG to sign the selected signature checksum file.

### verify
Ensures that the document checksum file is correct and that each signature checksum file is correct as well. Uses GPG to verify each signature. Determines whether all signatures are provided and valid.

### package
Calls the *verify* action first and then zips the original document, all checksum files, and all GPG signature files into an XZ file. It names the zip file the same as the document, with an additional datestamp of when it was packaged. Finally, all of the checksum and signature files are deleted, leaving only the original ODT and the zip file.
