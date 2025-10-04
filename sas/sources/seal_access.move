/// Seal access control for attestations using Private Data pattern

module sas::seal_access;

use sas::attestation::{Self, Attestation};

const ENoAccess: u64 = 0;

/// Compute the Seal key ID for an attestation using nonce
/// Key ID format: [attestor address][nonce]
/// This is used when encrypting data for an attestation
/// The full Seal ID will be [pkg id][attestor address][nonce]
/// 
/// Using nonce instead of attestation_id allows encryption before attestation creation
public fun compute_key_id(attestor: address, nonce: vector<u8>): vector<u8> {
    let mut blob = attestor.to_bytes();
    blob.append(nonce);
    blob
}

/// Check access policy for an encrypted attestation
/// Rules:
/// 1. The attestation must be encrypted
/// 2. Only the owner of the Attestation object (recipient) can call this function
///    (This is enforced by MoveVM when the function is called with object reference)
/// 3. The Seal ID must match the computed key ID: [attestor][nonce]
fun check_policy(id: vector<u8>, attestation: &Attestation): bool {
    
    // Check if the attestation is encrypted
    if (!attestation::is_encrypted(attestation)) {
        return false
    };

    // Get nonce from attestation (for encrypted attestations, nonce should be set)
    let nonce_opt = attestation::seal_nonce(attestation);
    if (option::is_none(&nonce_opt)) {
        return false
    };

    // Compute the expected key ID using attestor and nonce
    let attestor_addr = attestation::attestor(attestation);
    let nonce = *option::borrow(&nonce_opt);
    let expected_key_id = compute_key_id(attestor_addr, nonce);

    // Check if the provided Seal ID matches the expected key ID
    id == expected_key_id
}

/// Seal approve function for attestations
/// This function is called by Seal key servers to verify access permissions
/// Entry function that Seal key servers will call to verify access
/// 
/// Access control:
/// - Only the owner of the Attestation object (recipient) can call this function
/// - In Sui Move, to pass an owned object as &Attestation, the caller must use tx.object(id)
/// - Only the object owner can use tx.object(id) in their transaction, so only the owner
///   can construct a valid transaction that calls this function
/// - When Seal key server validates the transaction via dry_run_transaction_block,
///   it will fail if the transaction signer is not the object owner
/// - The Seal ID must match: [attestor address][nonce]
entry fun seal_approve(
    id: vector<u8>,
    attestation: &attestation::Attestation
) {
    assert!(check_policy(id, attestation), ENoAccess);
}

