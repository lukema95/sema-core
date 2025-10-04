module aas::schema {
    use std::bcs;
    use std::string::{String};
    use std::vector;

    use aptos_framework::event;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::timestamp;
    
    use aptos_std::table::{Table};
    use aptos_std::aptos_hash::{keccak256};

    use aas::package_manager;

    friend aas::aas;

    /*********** Structs ***********/

    /// Schema struct to store the schema information
    struct Schema has key {
        name: String,
        description: String,
        url: String,
        creator: address,
        created_at: u64,
        schema: vector<u8>,
        revokable: bool,
        resolver: address,
        tx_hash: vector<u8>,
    }

    struct SchemaData {
        name: String,
        description: String,
        url: String,
        creator: address,
        created_at: u64,
        schema: vector<u8>,
        revokable: bool,
        resolver: address,
        tx_hash: vector<u8>,
    }

    /// Schema registry struct to store the mapping from creator to schemas
    struct SchemaRegistry has key {
        schemas: Table<address, Object<Schema>>,
    }

    /*********** Events ***********/

    #[event]
    /// Event emitted when a schema is created
    struct SchemaCreated has drop, store {
        schema_address: address,
        name: String,
        description: String,
        url: String,
        creator: address,
        created_at: u64,
        revokable: bool,
        resolver: address,
        schema: vector<u8>,
    }

    /*********** Public Functions ***********/

    public(friend) fun create_schema(
        creator: address,
        name: String,
        description: String,
        url: String,
        revokable: bool,
        resolver: address,
        schema: vector<u8>
    ): address {
        let seeds = get_schema_seeds(name, description, url, revokable, resolver, schema);
        let constructor_ref = object::create_named_object(&package_manager::get_signer(), seeds);
        let object_signer = &object::generate_signer(&constructor_ref);
      
        let now = timestamp::now_seconds();

        move_to(object_signer, Schema {
            name: name,
            description: description,
            url: url,
            creator: creator,
            created_at: now,
            schema: schema,
            revokable: revokable,
            resolver: resolver,
            tx_hash: vector::empty(),
        });

        let schema_object = object::object_from_constructor_ref<Schema>(&constructor_ref);
        let schema_address = object::object_address<Schema>(&schema_object);
        
        event::emit(
            SchemaCreated {
                schema_address: schema_address,
                name: name,
                description: description,
                url: url,
                creator: creator,
                created_at: now,
                schema: schema,
                revokable: revokable,
                resolver: resolver,
            }
        );

        schema_address
    }

    /*********** View Functions ***********/

    #[view]
    public fun schema_data(schema_address: address): SchemaData acquires Schema {
        let schema = get_schema(schema_address);
        SchemaData {
            name: schema.name,
            description: schema.description,
            url: schema.url,
            creator: schema.creator,
            created_at: schema.created_at,
            schema: schema.schema,
            revokable: schema.revokable,
            resolver: schema.resolver,
            tx_hash: schema.tx_hash,
        }
    }

    #[view]
    public fun schema_unpacked(schema_address: address): (
        String, 
        String, 
        String, 
        address, 
        u64, 
        vector<u8>, 
        bool, 
        address, 
    ) acquires Schema {
        let schema = get_schema(schema_address);
        (
            schema.name, 
            schema.description, 
            schema.url, 
            schema.creator, 
            schema.created_at, 
            schema.schema, 
            schema.revokable, 
            schema.resolver, 
        )
    }

    #[view]
    public fun schema_creator(schema_address: address): address acquires Schema {
        let schema = get_schema(schema_address);
        schema.creator
    }

    #[view]
    public fun schema_revokable(schema_address: address): bool acquires Schema {
        let schema = get_schema(schema_address);
        schema.revokable
    }

    #[view]
    public fun schema_resolver(schema_address: address): address acquires Schema {
        let schema = get_schema(schema_address);
        schema.resolver
    }

    #[view]
    public fun schema_exists(schema_address: address): bool {
        exists<Schema>(schema_address)
    }

    #[view]
    public fun get_schema_address(
        name: String, 
        description: String, 
        url: String, 
        revokable: bool, 
        resolver: address, 
        schema: vector<u8>
    ): address {
        let seeds = get_schema_seeds(name, description, url, revokable, resolver, schema);
        object::create_object_address(&package_manager::get_signer_address(), seeds)
    }

    #[view]
    public fun get_schema_seeds(
        name: String, 
        description: String, 
        url: String, 
        revokable: bool, 
        resolver: address,
        schema: vector<u8>
    ): vector<u8> {
        let seed = vector::empty();
        vector::append(&mut seed, bcs::to_bytes(&name));
        vector::append(&mut seed, bcs::to_bytes(&description));
        vector::append(&mut seed, bcs::to_bytes(&url));
        vector::append(&mut seed, bcs::to_bytes(&revokable));
        vector::append(&mut seed, bcs::to_bytes(&resolver));
        vector::append(&mut seed, schema);
        keccak256(seed)
    }

    inline fun get_schema(schema_address: address): &Schema acquires Schema {
        borrow_global<Schema>(schema_address)
    }

}