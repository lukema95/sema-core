module sas::attestation {
    // === Imports ===
    use sui::{
        url::{Url},
        event::{emit},
        hash,
    };
    use std::string;

    // === Constants ===
    const STORAGE_TYPE_ON_CHAIN: u8 = 0;
    const STORAGE_TYPE_OFF_CHAIN: u8 = 1;  // Off-chain storage, default to Walrus

    // === Events ===
    public struct AttestationCreated has copy, drop {
        /// 0: Attest, 1: AttestWithResolver
        event_type: u8,
        id: address,
        schema: address,
        ref_attestation: address,
        time: u64,
        expiration_time: u64,
        revokable: bool,
        attestor: address,
        recipient: address,
        
        // Storage type
        storage_type: u8,
        
        // Data (determined by storage_type)
        data: vector<u8>,               // Contains actual data for ON_CHAIN, empty for OFF_CHAIN
        walrus_sui_object_id: address,  // Sui object ID of Walrus blob (for OFF_CHAIN)
        walrus_blob_id: vector<u8>,     // Walrus blob ID (base64url string as bytes) (for OFF_CHAIN)
        data_hash: vector<u8>,          // Used for OFF_CHAIN
        encrypted: bool,                // Used for OFF_CHAIN
        seal_nonce: Option<vector<u8>>, // Seal encryption nonce (for encrypted OFF_CHAIN)
        seal_policy_id: Option<address>,// Used for other access patterns (optional)
        
        name: string::String,
        description: string::String,
        url: Url,
    }

    // === Structs ===
    public struct Attestation has key {
        id: UID,
        schema: address,
        ref_attestation: address,
        time: u64,
        expiration_time: u64,
        revokable: bool,
        attestor: address,
        
        // Storage type identifier
        storage_type: u8,  // 0 = ON_CHAIN, 1 = OFF_CHAIN (default: Walrus)
        
        // Method 1: On-chain storage (backward compatible, original field)
        // Used when storage_type == ON_CHAIN
        data: vector<u8>,  // Preserved for backward compatibility
        
        // Method 2: Off-chain storage (default: Walrus)
        // Used when storage_type == OFF_CHAIN
        walrus_sui_object_id: address,     // Sui object ID of Walrus blob (for OFF_CHAIN)
        walrus_blob_id: vector<u8>,        // Walrus blob ID (base64url string as bytes) (for OFF_CHAIN)
        data_hash: vector<u8>,             // Original data hash (for integrity verification)
        encrypted: bool,                   // Whether data is encrypted
        seal_nonce: Option<vector<u8>>,    // Seal encryption nonce (for encrypted OFF_CHAIN)
        seal_policy_id: Option<address>,   // Seal access policy ID (for other patterns, optional)
        
        // Metadata (preserved)
        name: string::String,
        description: string::String,
        url: Url,
    }

    // === Public-View Functions ===
    public fun schema(self: &Attestation): address {
        self.schema
    }

    public fun ref_attestation(self: &Attestation): address {
        self.ref_attestation
    }

    public fun attestor(self: &Attestation): address {
        self.attestor
    }

    public fun time(self: &Attestation): u64 {
        self.time
    }

    public fun revokable(self: &Attestation): bool {
        self.revokable
    }

    public fun expiration_time(self: &Attestation): u64 {
        self.expiration_time
    }

    /// Get storage type
    public fun storage_type(self: &Attestation): u8 {
        self.storage_type
    }

    /// Check if storage is on-chain
    public fun is_on_chain_storage(self: &Attestation): bool {
        self.storage_type == STORAGE_TYPE_ON_CHAIN
    }

    /// Check if storage is off-chain (default: Walrus)
    public fun is_off_chain_storage(self: &Attestation): bool {
        self.storage_type == STORAGE_TYPE_OFF_CHAIN
    }

    /// Get data - automatically returns based on storage type
    /// For ON_CHAIN: returns the data field directly
    /// For OFF_CHAIN: returns empty (actual data needs to be downloaded from off-chain storage, default: Walrus)
    public fun data(self: &Attestation): vector<u8> {
        if (self.storage_type == STORAGE_TYPE_ON_CHAIN) {
            *&self.data
        } else {
            // For off-chain storage, return empty (actual data needs to be downloaded from off-chain storage, default: Walrus)
            vector::empty()
        }
    }

    /// Get data hash (for off-chain storage)
    public fun data_hash(self: &Attestation): Option<vector<u8>> {
        if (self.storage_type == STORAGE_TYPE_OFF_CHAIN) {
            option::some(*&self.data_hash)
        } else {
            option::none()
        }
    }

    /// Get Walrus Sui object ID (for off-chain storage)
    public fun walrus_sui_object_id(self: &Attestation): Option<address> {
        if (self.storage_type == STORAGE_TYPE_OFF_CHAIN) {
            option::some(self.walrus_sui_object_id)
        } else {
            option::none()
        }
    }

    /// Get off-chain blob ID (default: Walrus blob ID as bytes, base64url string)
    public fun walrus_blob_id(self: &Attestation): Option<vector<u8>> {
        if (self.storage_type == STORAGE_TYPE_OFF_CHAIN) {
            option::some(*&self.walrus_blob_id)
        } else {
            option::none()
        }
    }

    /// Get Seal nonce (for encrypted off-chain storage)
    public fun seal_nonce(self: &Attestation): Option<vector<u8>> {
        if (self.storage_type == STORAGE_TYPE_OFF_CHAIN && self.encrypted) {
            *&self.seal_nonce
        } else {
            option::none()
        }
    }

    /// Check if data is encrypted
    public fun is_encrypted(self: &Attestation): bool {
        if (self.storage_type == STORAGE_TYPE_OFF_CHAIN) {
            self.encrypted
        } else {
            false  // On-chain storage is not encrypted
        }
    }

    /// Get Seal policy ID if exists
    public fun seal_policy_id(self: &Attestation): Option<address> {
        if (self.storage_type == STORAGE_TYPE_OFF_CHAIN) {
            *&self.seal_policy_id
        } else {
            option::none()
        }
    }

    /// Verify data integrity (for off-chain storage)
    public fun verify_data_integrity(
        self: &Attestation,
        data: vector<u8>
    ): bool {
        assert!(self.storage_type == STORAGE_TYPE_OFF_CHAIN, 0);
        let computed_hash = hash::blake2b256(&data);
        computed_hash == *&self.data_hash
    }

    public fun name(self: &Attestation): string::String {
        self.name
    }

    public fun description(self: &Attestation): string::String {
        self.description
    }

    public fun url(self: &Attestation): Url {
        self.url
    }

    // === Internal Functions ===

    // Method 1: Create on-chain storage attestation (backward compatible)
    public(package) fun create_attestation_on_chain(
        schema: address,
        ref_attestation: address,
        time: u64,
        expiration_time: u64,
        revokable: bool,
        attestor: address,
        recipient: address,
        data: vector<u8>,  // Data stored on-chain
        name: string::String,
        description: string::String,
        url: Url,
        event_type: u8,
        ctx: &mut TxContext
    ): address {
        let id = object::new(ctx);
        let attest = Attestation {
            id,
            schema,
            ref_attestation,
            time,
            expiration_time,
            revokable,
            attestor,
            storage_type: STORAGE_TYPE_ON_CHAIN,
            data,  // On-chain storage
            walrus_sui_object_id: @0x0,  // Not used (on-chain storage)
            walrus_blob_id: vector::empty(),  // Not used (on-chain storage)
            data_hash: vector::empty(),  // Not used (on-chain storage)
            encrypted: false,
            seal_nonce: option::none(),
            seal_policy_id: option::none(),
            name,
            description,
            url,
        };

        let attestation_address = object::id_address(&attest);
        
        emit(AttestationCreated {
            event_type,
            id: attestation_address,
            schema,
            ref_attestation,
            time,
            expiration_time,
            revokable,
            attestor,
            recipient,
            storage_type: STORAGE_TYPE_ON_CHAIN,
            data: *&attest.data,                // Event contains data
            walrus_sui_object_id: @0x0,         // Not used (on-chain storage)
            walrus_blob_id: vector::empty(),    // Not used (on-chain storage)
            data_hash: vector::empty(),         // Not used (on-chain storage)
            encrypted: false,
            seal_nonce: option::none(),
            seal_policy_id: option::none(),
            name: *&attest.name,
            description: *&attest.description,
            url: *&attest.url,
        });

        transfer::transfer(attest, recipient);
        attestation_address
    }

    // Method 2: Create off-chain storage attestation (default: Walrus)
    public(package) fun create_attestation_off_chain(
        schema: address,
        ref_attestation: address,
        time: u64,
        expiration_time: u64,
        revokable: bool,
        attestor: address,
        recipient: address,
        walrus_sui_object_id: address,
        walrus_blob_id: vector<u8>,
        data_hash: vector<u8>,
        encrypted: bool,
        seal_nonce: Option<vector<u8>>,
        seal_policy_id: Option<address>,
        name: string::String,
        description: string::String,
        url: Url,
        event_type: u8,
        ctx: &mut TxContext
    ): address {
        let id = object::new(ctx);
        let attest = Attestation {
            id,
            schema,
            ref_attestation,
            time,
            expiration_time,
            revokable,
            attestor,
            storage_type: STORAGE_TYPE_OFF_CHAIN,
            data: vector::empty(),  // Data not stored on-chain (stored off-chain, default: Walrus)
            walrus_sui_object_id,
            walrus_blob_id,
            data_hash,
            encrypted,
            seal_nonce,
            seal_policy_id,
            name,
            description,
            url,
        };

        let attestation_address = object::id_address(&attest);
        
        emit(AttestationCreated {
            event_type,
            id: attestation_address,
            schema,
            ref_attestation,
            time,
            expiration_time,
            revokable,
            attestor,
            recipient,
            storage_type: STORAGE_TYPE_OFF_CHAIN,
            data: vector::empty(),  // Event does not contain actual data (stored off-chain, default: Walrus)
            walrus_sui_object_id,
            walrus_blob_id,
            data_hash,
            encrypted,
            seal_nonce,
            seal_policy_id,
            name: *&attest.name,
            description: *&attest.description,
            url: *&attest.url,
        });

        transfer::transfer(attest, recipient);
        attestation_address
    }

    // Backward compatibility: Preserve original create_attestation function (defaults to on-chain storage)
    public(package) fun create_attestation(
        schema: address,
        ref_attestation: address,
        time: u64,
        expiration_time: u64,
        revokable: bool,
        attestor: address,
        recipient: address,
        data: vector<u8>,
        name: string::String,
        description: string::String,
        url: Url,
        event_type: u8,
        ctx: &mut TxContext
    ): address {
        create_attestation_on_chain(
            schema,
            ref_attestation,
            time,
            expiration_time,
            revokable,
            attestor,
            recipient,
            data,
            name,
            description,
            url,
            event_type,
            ctx
        )
    }
}