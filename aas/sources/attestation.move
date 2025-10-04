module aas::attestation {
    use std::bcs;
    use std::string;
    use std::string::String;
    use std::vector;

    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use aptos_std::aptos_hash::{blake2b_256, keccak256};

    use aas::package_manager;

    friend aas::aas;

    /*********** Structs ***********/

    const STORAGE_TYPE_ON_CHAIN: u8 = 0;
    const STORAGE_TYPE_OFF_CHAIN: u8 = 1;

    /// Attestation struct to store the attestation information
    struct Attestation has key {
        schema: address,
        ref_attestation: address,
        time: u64,
        expiration_time: u64,
        revocation_time: u64,
        revokable: bool,
        attestor: address,
        recipient: address,
        storage_type: u8,
        data: vector<u8>,
        data_hash: vector<u8>,
        shelby_account: address,
        shelby_blob_name: String,
        shelby_blob_merkle_root: vector<u8>,
        shelby_register_tx_hash: vector<u8>,
    }

    struct AttestationData {
        schema: address,
        ref_attestation: address,
        time: u64,
        expiration_time: u64,
        revocation_time: u64,
        revokable: bool,
        attestor: address,
        recipient: address,
        storage_type: u8,
        data: vector<u8>,
        data_hash: vector<u8>,
        shelby_account: address,
        shelby_blob_name: String,
        shelby_blob_merkle_root: vector<u8>,
        shelby_register_tx_hash: vector<u8>,
    }

    #[event]
    /// Event emitted when a new attestation is created
    struct AttestationCreated has drop, store {
        attestation_address: address,
        schema: address,
        ref_attestation: address,
        time: u64,
        expiration_time: u64,
        revokable: bool,
        attestor: address,
        recipient: address,
        storage_type: u8,
        data: vector<u8>,
        data_hash: vector<u8>,
        shelby_account: address,
        shelby_blob_name: String,
        shelby_blob_merkle_root: vector<u8>,
        shelby_register_tx_hash: vector<u8>,
    }

    #[event]
    /// Event emitted when an attestation is revoked
    struct AttestationRevoked has drop, store {
        attestation_address: address,
        revocation_time: u64,
    }

    /*********** Public Friend Functions ***********/

    public(friend) fun create_attestation(
        attestor: address, 
        recipient: address,
        schema_addr: address, 
        ref_attestation: address, 
        expiration_time: u64, 
        revokable: bool, 
        data: vector<u8>
    ): address {
        let now = timestamp::now_seconds();
        let seeds = get_attestation_seeds(attestor, schema_addr, recipient, ref_attestation, expiration_time, revokable, now, data);
        let constructor_ref = object::create_named_object(&package_manager::get_signer(), seeds);
        let object_signer = &object::generate_signer(&constructor_ref);

        move_to(object_signer, Attestation {
            schema: schema_addr,
            ref_attestation: ref_attestation,
            time: now,
            expiration_time: expiration_time,
            revokable: revokable,
            revocation_time: 0,
            attestor: attestor,
            recipient: recipient,
            storage_type: STORAGE_TYPE_ON_CHAIN,
            data: data,
            data_hash: vector::empty(),
            shelby_account: @0x0,
            shelby_blob_name: string::utf8(b""),
            shelby_blob_merkle_root: vector::empty(),
            shelby_register_tx_hash: vector::empty(),
        });

        let attestation_object = object::object_from_constructor_ref<Attestation>(&constructor_ref);
        let attestation_address = object::object_address<Attestation>(&attestation_object);
        
        event::emit(
            AttestationCreated {
                attestation_address: attestation_address,
                schema: schema_addr,
                ref_attestation: ref_attestation,
                time: now,
                expiration_time: expiration_time,
                revokable: revokable,
                attestor: attestor,
                recipient: recipient,
                storage_type: STORAGE_TYPE_ON_CHAIN,
                data: data,
                data_hash: vector::empty(),
                shelby_account: @0x0,
                shelby_blob_name: string::utf8(b""),
                shelby_blob_merkle_root: vector::empty(),
                shelby_register_tx_hash: vector::empty(),
            }
        );

        attestation_address
    }

    public(friend) fun create_attestation_off_chain(
        attestor: address,
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
        let now = timestamp::now_seconds();
        let seeds = get_attestation_seeds_off_chain(
            attestor,
            schema_addr,
            recipient,
            ref_attestation,
            expiration_time,
            revokable,
            now,
            data_hash,
            shelby_account,
            shelby_blob_name,
        );
        let constructor_ref = object::create_named_object(&package_manager::get_signer(), seeds);
        let object_signer = &object::generate_signer(&constructor_ref);

        move_to(object_signer, Attestation {
            schema: schema_addr,
            ref_attestation: ref_attestation,
            time: now,
            expiration_time: expiration_time,
            revokable: revokable,
            revocation_time: 0,
            attestor: attestor,
            recipient: recipient,
            storage_type: STORAGE_TYPE_OFF_CHAIN,
            data: vector::empty(),
            data_hash: data_hash,
            shelby_account: shelby_account,
            shelby_blob_name: shelby_blob_name,
            shelby_blob_merkle_root: shelby_blob_merkle_root,
            shelby_register_tx_hash: shelby_register_tx_hash,
        });

        let attestation_object = object::object_from_constructor_ref<Attestation>(&constructor_ref);
        let attestation_address = object::object_address<Attestation>(&attestation_object);

        event::emit(
            AttestationCreated {
                attestation_address: attestation_address,
                schema: schema_addr,
                ref_attestation: ref_attestation,
                time: now,
                expiration_time: expiration_time,
                revokable: revokable,
                attestor: attestor,
                recipient: recipient,
                storage_type: STORAGE_TYPE_OFF_CHAIN,
                data: vector::empty(),
                data_hash: data_hash,
                shelby_account: shelby_account,
                shelby_blob_name: shelby_blob_name,
                shelby_blob_merkle_root: shelby_blob_merkle_root,
                shelby_register_tx_hash: shelby_register_tx_hash,
            }
        );

        attestation_address
    }

    public(friend) fun revoke_attestation(attestation_address: address) acquires Attestation {
        let attestation = unchecked_mut_attestation(attestation_address);
        attestation.revocation_time = timestamp::now_seconds();

        event::emit(
            AttestationRevoked {
                attestation_address: attestation_address,
                revocation_time: attestation.revocation_time,
            }
        );
    }

    /*********** View Functions ***********/

    #[view]
    public fun attestation_data(attestation_address: address): AttestationData acquires Attestation {
        let attestation = get_attestation(attestation_address);
        AttestationData {
            schema: attestation.schema,
            ref_attestation: attestation.ref_attestation,
            time: attestation.time,
            expiration_time: attestation.expiration_time,
            revocation_time: attestation.revocation_time,
            revokable: attestation.revokable,
            attestor: attestation.attestor,
            recipient: attestation.recipient,
            storage_type: attestation.storage_type,
            data: attestation.data,
            data_hash: attestation.data_hash,
            shelby_account: attestation.shelby_account,
            shelby_blob_name: attestation.shelby_blob_name,
            shelby_blob_merkle_root: attestation.shelby_blob_merkle_root,
            shelby_register_tx_hash: attestation.shelby_register_tx_hash,
        }
    }

    #[view]
    public fun attestation_unpacked(attestation_address: address): (
        address, 
        address, 
        u64, 
        u64, 
        u64, 
        bool,
        address, 
        address, 
        u8,
        vector<u8>,
        vector<u8>,
        address,
        String,
        vector<u8>,
        vector<u8>,
    ) acquires Attestation {
        let attestation = get_attestation(attestation_address);
        (
            attestation.schema, 
            attestation.ref_attestation, 
            attestation.time, 
            attestation.expiration_time,
            attestation.revocation_time,
            attestation.revokable,
            attestation.attestor,
            attestation.recipient,
            attestation.storage_type,
            attestation.data,
            attestation.data_hash,
            attestation.shelby_account,
            attestation.shelby_blob_name,
            attestation.shelby_blob_merkle_root,
            attestation.shelby_register_tx_hash,
        )
    }

    #[view]
    public fun attestation_exists(attestation_address: address): bool {
        exists<Attestation>(attestation_address)
    }

    #[view]
    public fun attestation_revoked(attestation_address: address): bool acquires Attestation {
        let attestation = get_attestation(attestation_address);
        attestation.revocation_time != 0
    }

    #[view]
    public fun storage_type(attestation_address: address): u8 acquires Attestation {
        let attestation = get_attestation(attestation_address);
        attestation.storage_type
    }

    #[view]
    public fun data_hash(attestation_address: address): vector<u8> acquires Attestation {
        let attestation = get_attestation(attestation_address);
        attestation.data_hash
    }

    #[view]
    public fun shelby_account(attestation_address: address): address acquires Attestation {
        let attestation = get_attestation(attestation_address);
        attestation.shelby_account
    }

    #[view]
    public fun shelby_blob_name(attestation_address: address): String acquires Attestation {
        let attestation = get_attestation(attestation_address);
        attestation.shelby_blob_name
    }

    #[view]
    public fun verify_data_integrity(attestation_address: address, data: vector<u8>): bool acquires Attestation {
        let attestation = get_attestation(attestation_address);
        if (attestation.storage_type != STORAGE_TYPE_OFF_CHAIN) {
            return false
        };
        blake2b_256(data) == *&attestation.data_hash
    }

    #[view]
    public fun get_attestation_address(
        attestor: address, 
        schema: address, 
        recipient: address, 
        ref_id: address, 
        expiration_time: u64, 
        revokable: bool, 
        now: u64, 
        data: vector<u8>
    ): address {
        let seeds = get_attestation_seeds(attestor, schema, recipient, ref_id, expiration_time, revokable, now, data);
        object::create_object_address(&package_manager::get_signer_address(), seeds)
    }

    #[view]
    public fun get_attestation_address_off_chain(
        attestor: address,
        schema: address,
        recipient: address,
        ref_id: address,
        expiration_time: u64,
        revokable: bool,
        now: u64,
        data_hash: vector<u8>,
        shelby_account: address,
        shelby_blob_name: String,
    ): address {
        let seeds = get_attestation_seeds_off_chain(
            attestor,
            schema,
            recipient,
            ref_id,
            expiration_time,
            revokable,
            now,
            data_hash,
            shelby_account,
            shelby_blob_name,
        );
        object::create_object_address(&package_manager::get_signer_address(), seeds)
    }

    #[view]
    public fun get_attestation_seeds(
        attestor: address, 
        schema: address, 
        recipient: address, 
        ref_id: address, 
        expiration_time: u64, 
        revokable: bool, 
        now: u64, 
        data: vector<u8>
    ): vector<u8> {
        let seed = bcs::to_bytes(&attestor);
        vector::append(&mut seed, bcs::to_bytes(&schema));
        vector::append(&mut seed, bcs::to_bytes(&recipient));
        vector::append(&mut seed, bcs::to_bytes(&ref_id));
        vector::append(&mut seed, bcs::to_bytes(&expiration_time));
        vector::append(&mut seed, bcs::to_bytes(&revokable));
        vector::append(&mut seed, bcs::to_bytes(&now));
        vector::append(&mut seed, data);
        keccak256(seed)
    }

    #[view]
    public fun get_attestation_seeds_off_chain(
        attestor: address,
        schema: address,
        recipient: address,
        ref_id: address,
        expiration_time: u64,
        revokable: bool,
        now: u64,
        data_hash: vector<u8>,
        shelby_account: address,
        shelby_blob_name: String,
    ): vector<u8> {
        let seed = bcs::to_bytes(&attestor);
        vector::append(&mut seed, bcs::to_bytes(&schema));
        vector::append(&mut seed, bcs::to_bytes(&recipient));
        vector::append(&mut seed, bcs::to_bytes(&ref_id));
        vector::append(&mut seed, bcs::to_bytes(&expiration_time));
        vector::append(&mut seed, bcs::to_bytes(&revokable));
        vector::append(&mut seed, bcs::to_bytes(&now));
        vector::append(&mut seed, data_hash);
        vector::append(&mut seed, bcs::to_bytes(&shelby_account));
        vector::append(&mut seed, bcs::to_bytes(&shelby_blob_name));
        keccak256(seed)
    }

    inline fun unchecked_mut_attestation(attestation_address: address): &mut Attestation acquires Attestation {
        borrow_global_mut<Attestation>(attestation_address)
    }

    inline fun get_attestation(attestation_address: address): &Attestation acquires Attestation {
        borrow_global<Attestation>(attestation_address)
    }

}
