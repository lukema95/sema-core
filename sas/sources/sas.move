
/// Module: sas
module sas::sas {
    // === Imports ===
    use sui::{
        tx_context::{sender},
        url,
        clock::{Self, Clock},
    };
    use std::string;
    
    use sas::admin::{Admin};
    use sas::schema::{Self, Schema, Request, ResolverBuilder};
    use sas::schema_registry::{SchemaRegistry};
    use sas::attestation;
    use sas::attestation_registry::{AttestationRegistry};

    // === Errors ===
    const EExpired: u64 = 0;
    const ERefIdNotFound: u64 = 1;
    const EHasResolver: u64 = 2;
    const EInvalidLength: u64 = 3;

    // === Constants ===
    const ATT_TYPE_ATTEST: u8 = 0;
    const ATT_TYPE_ATTEST_WITH_RESOLVER: u8 = 1;

    // === Public Functions ===
    public fun register_schema(
        schema_registry: &mut SchemaRegistry, 
        schema: vector<u8>, 
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        revokable: bool,
        ctx: &mut TxContext
    ): Admin {
        schema::new(
            schema_registry, 
            schema, 
            name, 
            description, 
            url, 
            revokable, 
            ctx
        )
    }

    public fun register_schema_with_resolver(
        schema_registry: &mut SchemaRegistry,
        schema: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        revokable: bool,
        ctx: &mut TxContext,
    ): (ResolverBuilder, Admin, Schema) {
        schema::new_with_resolver(
            schema_registry, 
            schema, 
            name, 
            description, 
            url, 
            revokable, 
            ctx
        )
    }

    public fun attest_multi(
        schema_record: &mut Schema,
        attestation_registry: &mut AttestationRegistry,
        ref_attestation_vec: vector<address>,
        recipients_vec: vector<address>,
        expiration_times_vec: vector<u64>,
        datas_vec: vector<vector<u8>>,
        names_vec: vector<vector<u8>>,
        descriptions_vec: vector<vector<u8>>,
        urls_vec: vector<vector<u8>>,
        time: &Clock,
        ctx: &mut TxContext
    ) {
        let len = vector::length(&recipients_vec);
        assert!(len == vector::length(&ref_attestation_vec), EInvalidLength);
        assert!(len == vector::length(&expiration_times_vec), EInvalidLength);
        assert!(len == vector::length(&datas_vec), EInvalidLength);
        assert!(len == vector::length(&names_vec), EInvalidLength);
        assert!(len == vector::length(&descriptions_vec), EInvalidLength);
        assert!(len == vector::length(&urls_vec), EInvalidLength);
        let mut i = 0;
        while (i < len) {
            attest(
                schema_record, 
                attestation_registry, 
                ref_attestation_vec[i], 
                recipients_vec[i], 
                expiration_times_vec[i], 
                datas_vec[i], 
                names_vec[i], 
                descriptions_vec[i], 
                urls_vec[i], 
                time, 
                ctx
            );
            i = i + 1;
        };
    }

    public fun attest(
        schema_record: &mut Schema,
        attestation_registry: &mut AttestationRegistry,
        ref_attestation: address,
        recipient: address,
        expiration_time: u64,
        data: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        time: &Clock,
        ctx: &mut TxContext
    ): address {
        assert!(!schema_record.has_resolver(), EHasResolver);
        if (ref_attestation != @0x0) {
            assert!(attestation_registry.is_exist(ref_attestation), ERefIdNotFound);
        };
        
        let attestor = ctx.sender();

        if (expiration_time != 0) {
            assert!(time.timestamp_ms() < expiration_time, EExpired);
        };

        let attestation_address = attestation::create_attestation(
            object::id_address(schema_record),
            ref_attestation,
            clock::timestamp_ms(time),
            expiration_time,
            schema_record.revokable(),
            attestor,
            recipient,
            data,
            string::utf8(name),
            string::utf8(description),
            url::new_unsafe_from_bytes(url),
            ATT_TYPE_ATTEST,
            ctx
        );

        attestation_registry.registry(attestation_address, schema_record.addy());
        attestation_address
    }

    /// Attest with off-chain storage (default: Walrus)
    public fun attest_off_chain(
        schema_record: &mut Schema,
        attestation_registry: &mut AttestationRegistry,
        ref_attestation: address,
        recipient: address,
        expiration_time: u64,
        walrus_sui_object_id: address,
        walrus_blob_id: vector<u8>,
        data_hash: vector<u8>,
        encrypted: bool,
        seal_nonce: Option<vector<u8>>,
        seal_policy_id: Option<address>,
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        time: &Clock,
        ctx: &mut TxContext
    ): address {
        assert!(!schema_record.has_resolver(), EHasResolver);
        if (ref_attestation != @0x0) {
            assert!(attestation_registry.is_exist(ref_attestation), ERefIdNotFound);
        };
        
        let attestor = ctx.sender();

        if (expiration_time != 0) {
            assert!(time.timestamp_ms() < expiration_time, EExpired);
        };

        let attestation_address = attestation::create_attestation_off_chain(
            object::id_address(schema_record),
            ref_attestation,
            clock::timestamp_ms(time),
            expiration_time,
            schema_record.revokable(),
            attestor,
            recipient,
            walrus_sui_object_id,
            walrus_blob_id,
            data_hash,
            encrypted,
            seal_nonce,
            seal_policy_id,
            string::utf8(name),
            string::utf8(description),
            url::new_unsafe_from_bytes(url),
            ATT_TYPE_ATTEST,
            ctx
        );

        attestation_registry.registry(attestation_address, schema_record.addy());
        attestation_address
    }

    public fun attest_with_resolver(
        schema_record: &mut Schema,
        attestation_registry: &mut AttestationRegistry,
        ref_attestation: address,
        recipient: address,
        expiration_time: u64,
        data: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        time: &Clock,
        request: Request,
        ctx: &mut TxContext
    ): address {
        if (ref_attestation != @0x0) {
            assert!(attestation_registry.is_exist(ref_attestation), ERefIdNotFound);
        };

        let attestor = ctx.sender();

        if (expiration_time != 0) {
            assert!(time.timestamp_ms() < expiration_time, EExpired);
        };

        schema::finish_attest(schema_record, request);

        let attestation_address = attestation::create_attestation(
            object::id_address(schema_record),
            ref_attestation,
            clock::timestamp_ms(time),
            expiration_time,
            schema_record.revokable(),
            attestor,
            recipient,
            data,
            string::utf8(name),
            string::utf8(description),
            url::new_unsafe_from_bytes(url),
            ATT_TYPE_ATTEST_WITH_RESOLVER,
            ctx
        );

        attestation_registry.registry(attestation_address, schema_record.addy());
        attestation_address
    }

    public fun revoke_multi(
        admin: &Admin,
        attestation_registry: &mut AttestationRegistry,
        schema_record: &Schema,
        attestation_vec: vector<address>,
        ctx: &mut TxContext
    ) {
        let len = vector::length(&attestation_vec);
        let mut i = 0;
        while (i < len) {
            revoke(admin, attestation_registry, schema_record, attestation_vec[i], ctx);
            i = i + 1;
        };
    }

    public fun revoke(
        admin: &Admin,
        attestation_registry: &mut AttestationRegistry,
        schema_record: &Schema,
        attestation: address,
        ctx: &mut TxContext
    ) {
        assert!(!schema_record.has_resolver(), EHasResolver);
        attestation_registry.revoke(admin, schema_record, attestation, ctx);
    }

    public fun revoke_with_resolver(
        admin: &Admin,
        attestation_registry: &mut AttestationRegistry,
        schema_record: &Schema,
        attestation: address,
        request: Request,
        ctx: &mut TxContext
    ) {
        assert!(schema_record.has_resolver(), EHasResolver);

        schema::finish_revoke(schema_record, request);

        attestation_registry.revoke(admin, schema_record, attestation, ctx);
    }
}
