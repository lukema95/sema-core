module aas::aas {
    use std::error;
    use std::signer;
    use std::vector;
    use std::string::{Self, String};

    use aas::schema;
    use aas::attestation;
    use aas::resolver_dispatcher;
    
    /*********** Error Codes ***********/
    
    const ESTRING_TOO_LONG: u64 = 1;
    const ENOT_SCHEMA_CREATOR: u64 = 2;
    const E_NOT_REVOKABLE: u64 = 3;
    const EATTESTATION_NOT_FOUND: u64 = 4;
    const EATTESTATION_ALREADY_REVOKED: u64 = 5;
    const EATTESTATIONS_NOT_EXIST_AT_ADDRESS: u64 = 6;
    const ESCHEMA_NOT_FOUND: u64 = 7;
    const ERESOLVE_FAILED: u64 = 8;
    const EINVALID_LENGTH: u64 = 9;

    /*********** Entry Functions ***********/

    /// Create a new schema
    public entry fun create_schema(
        creator: &signer, 
        schema: vector<u8>, 
        name: String, 
        description: String, 
        url: String, 
        revokable: bool,
        resolver: address,
    ) {
        create_schema_and_get_schema_address(creator, schema, name, description, url, revokable, resolver);
    }

    /// Create multiple attestations
    public entry fun create_multi_attestations(
        attestor: &signer,
        recipients: vector<address>,
        schema_addr: address,
        ref_attestations: vector<address>,
        expiration_times: vector<u64>,
        revokable: bool,
        data: vector<vector<u8>>,
    ) {
        let len = vector::length(&recipients);
        assert!(len == vector::length(&ref_attestations), error::invalid_argument(EINVALID_LENGTH));
        assert!(len == vector::length(&expiration_times), error::invalid_argument(EINVALID_LENGTH));
        assert!(len == vector::length(&data), error::invalid_argument(EINVALID_LENGTH));
        for (i in 0..len) {
            let recipient = *vector::borrow(&recipients, i);
            let ref_attestation = *vector::borrow(&ref_attestations, i);
            let expiration_time = *vector::borrow(&expiration_times, i);
            let data = *vector::borrow(&data, i);
            create_attestation(
                attestor, 
                recipient, 
                schema_addr, 
                ref_attestation, 
                expiration_time, 
                revokable, 
                data
            );
        }
    }

    /// Create a new attestation
    public entry fun create_attestation(
        attestor: &signer, 
        recipient: address,
        schema_addr: address, 
        ref_attestation: address, 
        expiration_time: u64, 
        revokable: bool, 
        data: vector<u8>
    ) {
        create_attestation_and_get_address(attestor, recipient, schema_addr, ref_attestation, expiration_time, revokable, data);
    }

    /// Create a new off-chain attestation (Shelby)
    public entry fun create_attestation_off_chain(
        attestor: &signer,
        recipient: address,
        schema_addr: address,
        ref_attestation: address,
        expiration_time: u64,
        revokable: bool,
        data_hash: vector<u8>,
        shelby_account: address,
        shelby_blob_name: String,
        shelby_blob_merkle_root: vector<u8>,
        shelby_register_tx_hash: vector<u8>,
    ) {
        create_attestation_off_chain_and_get_address(
            attestor,
            recipient,
            schema_addr,
            ref_attestation,
            expiration_time,
            revokable,
            data_hash,
            shelby_account,
            shelby_blob_name,
            shelby_blob_merkle_root,
            shelby_register_tx_hash,
        );
    }

    /// Revoke multiple attestations
    public entry fun revoke_multi_attestations(
        admin: &signer,
        schema_addr: vector<address>,
        attestations: vector<address>,
    ) {
        let len = vector::length(&schema_addr);
        assert!(len == vector::length(&attestations), error::invalid_argument(EINVALID_LENGTH));
        for (i in 0..len) {
            let schema_addr = *vector::borrow(&schema_addr, i);
            let attestation = *vector::borrow(&attestations, i);
            revoke_attestation(admin, schema_addr, attestation);
        }
    }

    /// Revoke an attestation
    public entry fun revoke_attestation(
        admin: &signer,
        schema_addr: address,
        attestation: address,
    ) {
        let admin_addr = signer::address_of(admin);
        assert!(schema::schema_exists(schema_addr), error::invalid_argument(ESCHEMA_NOT_FOUND));
        assert!(attestation::attestation_exists(attestation), error::invalid_argument(EATTESTATION_NOT_FOUND));
        assert!(admin_addr == schema::schema_creator(schema_addr), error::invalid_argument(ENOT_SCHEMA_CREATOR));
        assert!(schema::schema_revokable(schema_addr), error::invalid_argument(E_NOT_REVOKABLE));
        assert!(!attestation::attestation_revoked(attestation), error::invalid_argument(EATTESTATION_ALREADY_REVOKED));
        
        let resolver = schema::schema_resolver(schema_addr);
        if (resolver != @0x0) {
            assert!(
                resolver_dispatcher::on_revoke(resolver, admin_addr, schema_addr, attestation),
                error::unauthenticated(ERESOLVE_FAILED)
            );
        };

        attestation::revoke_attestation(attestation);
    }

    /*********** Public Functions ***********/

    public fun create_schema_and_get_schema_address(
        creator: &signer, 
        schema: vector<u8>, 
        name: String, 
        description: String, 
        url: String, 
        revokable: bool,
        resolver: address,
    ): address {
        assert!(string::length(&name) < 128, error::invalid_argument(ESTRING_TOO_LONG));
        assert!(string::length(&description) < 512, error::invalid_argument(ESTRING_TOO_LONG));
        assert!(string::length(&url) < 512, error::invalid_argument(ESTRING_TOO_LONG));

        schema::create_schema(signer::address_of(creator), name, description, url, revokable, resolver, schema)
    }

    public fun create_attestation_and_get_address(
        attestor: &signer, 
        recipient: address,
        schema_addr: address, 
        ref_attestation: address, 
        expiration_time: u64, 
        revokable: bool, 
        data: vector<u8>
    ): address {
        assert!(!attestation::attestation_exists(ref_attestation), error::invalid_argument(EATTESTATIONS_NOT_EXIST_AT_ADDRESS));
        assert!(schema::schema_exists(schema_addr), error::invalid_argument(ESCHEMA_NOT_FOUND));
        let resolver = schema::schema_resolver(schema_addr);
        if (resolver != @0x0) {
            assert!(
                resolver_dispatcher::on_attest(resolver, signer::address_of(attestor), recipient, schema_addr, ref_attestation, expiration_time, revokable, data),
                error::unauthenticated(ERESOLVE_FAILED)
            );
        };
        
        attestation::create_attestation(signer::address_of(attestor), recipient, schema_addr, ref_attestation, expiration_time, revokable, data)
    }

    public fun create_attestation_off_chain_and_get_address(
        attestor: &signer,
        recipient: address,
        schema_addr: address,
        ref_attestation: address,
        expiration_time: u64,
        revokable: bool,
        data_hash: vector<u8>,
        shelby_account: address,
        shelby_blob_name: String,
        shelby_blob_merkle_root: vector<u8>,
        shelby_register_tx_hash: vector<u8>,
    ): address {
        assert!(!attestation::attestation_exists(ref_attestation), error::invalid_argument(EATTESTATIONS_NOT_EXIST_AT_ADDRESS));
        assert!(schema::schema_exists(schema_addr), error::invalid_argument(ESCHEMA_NOT_FOUND));
        let resolver = schema::schema_resolver(schema_addr);
        if (resolver != @0x0) {
            assert!(
                resolver_dispatcher::on_attest(
                    resolver,
                    signer::address_of(attestor),
                    recipient,
                    schema_addr,
                    ref_attestation,
                    expiration_time,
                    revokable,
                    data_hash,
                ),
                error::unauthenticated(ERESOLVE_FAILED)
            );
        };

        attestation::create_attestation_off_chain(
            signer::address_of(attestor),
            recipient,
            schema_addr,
            ref_attestation,
            expiration_time,
            revokable,
            data_hash,
            shelby_account,
            shelby_blob_name,
            shelby_blob_merkle_root,
            shelby_register_tx_hash,
        )
    }

}
