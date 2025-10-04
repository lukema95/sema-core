#[allow(lint(custom_state_change))]
module sas::schema {
    // === Imports ===
    use std::{
        string::{Self, String}, 
        type_name::{Self, TypeName}
    };
    use sui::{
        bag::{Self, Bag},
        url::{Self, Url},
        vec_map::{Self, VecMap},
        vec_set::{Self, VecSet},
        event::{emit},
    };
    use sas::schema_registry::{SchemaRegistry};
    use sas::admin::{Self, Admin};

    // ==== Errors ====
    const EWrongSchemaAddress: u64 = 0;
    const ENoResolver: u64 = 1;
    const EMustBeFinishRequest: u64 = 2;
    const ERuleNotApproved: u64 = 3;


    // ==== Events ====
    /// emitted when a schema is created
    public struct SchemaCreated has copy, drop {
        /// 0: SchemaCreated, 1: SchemaCreatedWithResolver
        event_type: u8,        
        schema_address: address,
        name: String,
        description: String,
        url: Url,
        creator: address,
        created_at: u64,
        schema: vector<u8>,
        revokable: bool,
        admin_cap: address
    }

    // ==== Constants ====
    const START_ATTEST: vector<u8> = b"START_ATTEST";
    const START_REVOKE: vector<u8> = b"START_REVOKE";

    // ==== Structs ====
    
    /// Schema struct to store schema data
    public struct Schema has key, store {
        id: UID,
        name: String,
        description: String,
        url: Url,
        creator: address,
        created_at: u64,
        schema: vector<u8>,
        revokable: bool,
        resolver: Option<Resolver>
    }

    public struct Resolver has store {
        rules: VecMap<String, VecSet<TypeName>>,
        config: Bag,
        resolver_address: address,
        resolver_module: vector<u8>
    }

    public struct ResolverBuilder {
        schema_address: address,
        resolver_address: address,
        resolver_module: vector<u8>,
        rules: VecMap<String, VecSet<TypeName>>,
        config: Bag
    }

    public struct Request {
        name: String,
        schema_address: address,
        approvals: VecSet<TypeName>
    }
  
    // === Public-Mutative Functions ===
    public fun start_attest(self: &Schema): Request {
        assert!(self.has_resolver(), ENoResolver);  
        new_request(self, START_ATTEST.to_string())
    }

    public fun finish_attest(self: &Schema, request: Request) {
        assert!(self.has_resolver(), ENoResolver);
        assert!(request.request_name() == START_ATTEST.to_string(), EMustBeFinishRequest);

        self.confirm(request);
    }

    public fun start_revoke(self: &Schema): Request {
        assert!(self.has_resolver(), ENoResolver);
        new_request(self, START_REVOKE.to_string())
    }

    public fun finish_revoke(self: &Schema, request: Request) {
        assert!(self.has_resolver(), ENoResolver);
        assert!(request.request_name() == START_REVOKE.to_string(), EMustBeFinishRequest);

        self.confirm(request);
    }

    public fun get_resolver_address(self: &Schema): address {
        if (self.has_resolver()) {
            option::borrow(&self.resolver).resolver_address
        } else {
            @0x0
        }
    }

    // === Public-View Functions ===
    public fun start_attest_name(): vector<u8> {
        START_ATTEST
    }

    public fun start_revoke_name(): vector<u8> {
        START_REVOKE
    }

    public fun schema(self: &Schema): vector<u8> {
        self.schema
    }

    public fun name(self: &Schema): String {
        self.name
    }

    public fun description(self: &Schema): String {
        self.description
    }

    public fun url(self: &Schema): Url {
        self.url
    }

    public fun created_at(self: &Schema): u64 {
        self.created_at
    }

    public fun creator(self: &Schema): address {
        self.creator
    }

    public fun revokable(self: &Schema): bool {
        self.revokable
    }

    public fun addy(self: &Schema): address {
        self.id.to_address()
    }

    public fun config<Rule: drop, Config: store>(
        self: &Schema
    ): &Config {
        self.resolver.borrow().config.borrow(type_name::with_defining_ids<Rule>())
    }

    public fun has_resolver(self: &Schema): bool {
        option::is_some(&self.resolver)
    }

    public fun resolver_address(self: &Schema): address {
        option::borrow(&self.resolver).resolver_address
    }

    public fun resolver_module(self: &Schema): vector<u8> {
        option::borrow(&self.resolver).resolver_module
    }

    public fun schema_address_from_request(request: &Request): address {
        request.schema_address
    }

    public fun request_name(request: &Request): String {
        request.name
    }

    public fun approvals(request: &Request): VecSet<TypeName> {
        request.approvals
    }

    public fun schema_address_from_builder(builder: &ResolverBuilder): address {
        builder.schema_address
    }
  
    public fun rules(builder: &ResolverBuilder): &VecMap<String, VecSet<TypeName>> {
        &builder.rules
    }

    public fun config_from_builder(builder: &ResolverBuilder): &Bag {
        &builder.config
    }

    // === Public Functions ===
    /// Create a new schema
    public fun new(
        schema_registry: &mut SchemaRegistry, 
        schema: vector<u8>, 
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        revokable: bool,
        ctx: &mut TxContext
        ): Admin {
        let schema_record = Schema {
            id: object::new(ctx),
            name: string::utf8(name),
            description: string::utf8(description),
            url: url::new_unsafe_from_bytes(url),
            creator: ctx.sender(),
            created_at: ctx.epoch_timestamp_ms(),
            schema: schema,
            revokable: revokable,
            resolver: option::none()
        };

        schema_registry.registry(schema_record.addy(), ctx);
        emit(
            SchemaCreated {
                event_type: 0,
                schema_address: schema_record.addy(),
                name: schema_record.name,
                description: schema_record.description,
                url: schema_record.url,
                creator: schema_record.creator,
                created_at: schema_record.created_at,
                schema: schema_record.schema,
                revokable: schema_record.revokable,
                admin_cap: @0x0
            }
        );

        let admin_cap = admin::new(schema_record.addy(), ctx);
        transfer::share_object(schema_record);

        admin_cap
    }

    public fun new_with_resolver(
        schema_registry: &mut SchemaRegistry,
        schema: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        revokable: bool,
        ctx: &mut TxContext,
    ): (ResolverBuilder, Admin, Schema) {
        let schema_record = Schema {
            id: object::new(ctx),
            name: string::utf8(name),
            description: string::utf8(description),
            url: url::new_unsafe_from_bytes(url),
            creator: ctx.sender(),
            created_at: ctx.epoch_timestamp_ms(),
            schema: schema,
            revokable: revokable,
            resolver: option::none()
        };

        schema_registry.registry(schema_record.addy(), ctx);

        let admin_cap = admin::new(schema_record.addy(), ctx);
        let resolver_builder = new_resolver_builder(&admin_cap, &schema_record, ctx);

        let admin_address = object::id_address(&admin_cap);
        let schema_address = schema_record.addy();

        emit(
            SchemaCreated {
                event_type: 1,
                schema_address: schema_address,
                name: schema_record.name,
                description: schema_record.description,
                url: schema_record.url,
                creator: schema_record.creator,
                created_at: schema_record.created_at,
                schema: schema_record.schema,
                revokable: schema_record.revokable,
                admin_cap: admin_address
            }
        );
        
        // transfer::share_object(schema_record);
        
        (
            resolver_builder,
            admin_cap,
            schema_record
        )
    }

    #[allow(lint(share_owned))]
    public fun share_schema(self: Schema) {
        transfer::share_object(self);
    }

    // Todo: Should add Admin Cap to this function?
    public fun add_resolver(
        schema_record: &mut Schema,
        resolver_builder: ResolverBuilder
    ) {
        let ResolverBuilder { rules, config, schema_address, resolver_address, resolver_module } = resolver_builder;
        assert!(object::id_address(schema_record) == schema_address, EWrongSchemaAddress);
        schema_record.resolver.fill(Resolver {
            rules: rules,
            config: config,
            resolver_address: resolver_address,
            resolver_module: resolver_module
        });
    }

    public fun new_request(self: &Schema, name: String): Request {
        Request {
            name: name,
            schema_address: object::id_address(self),
            approvals: vec_set::empty()
        }
    }

    // === Admin Functions ===
    public fun new_resolver_builder(
        admin: &Admin,
        schema_record: &Schema,
        ctx: &mut TxContext
    ): ResolverBuilder {
        admin.assert_schema(schema_record.addy());
        let mut rules = vec_map::empty();
        rules.insert(START_ATTEST.to_string(), vec_set::empty());
        rules.insert(START_REVOKE.to_string(), vec_set::empty());

        ResolverBuilder {
            schema_address: schema_record.addy(),
            resolver_address: @0x0,
            resolver_module: vector::empty(),
            rules: rules,
            config: bag::new(ctx)
        }
    }

    // === Public-Package Functions ===

    // === Private Functions ===
    fun confirm(self: &Schema, request: Request) {
        let resolver = self.resolver.borrow();
        let Request { name, schema_address, approvals } = request;

        assert!(object::id_address(self) == schema_address, EWrongSchemaAddress);

        let rules = (*resolver.rules.get(&name)).into_keys();

        let rules_len = rules.length();
        let mut i = 0;

        while (rules_len > i) {
            let rule = &rules[i];
            assert!(approvals.contains(rule), ERuleNotApproved);
            i = i + 1;
        }
    }

    // === Witness Functions ===
    public fun add_rule<Rule: drop>(
        resolver_builder: &mut ResolverBuilder,
        name: String,
        _: Rule
    ) {
        resolver_builder.rules.get_mut(&name).insert(type_name::with_defining_ids<Rule>());
    }

    public fun add_rule_config<Rule: drop, Config: store>(
        resolver_builder: &mut ResolverBuilder,
        _: Rule,
        config: Config
    ) {
        resolver_builder.config.add(type_name::with_defining_ids<Rule>(), config);
    }

    public fun add_resolver_address(
        resolver_builder: &mut ResolverBuilder,
        resolver_address: address
    ) {
        resolver_builder.resolver_address = resolver_address;
    }

    public fun add_resolver_module(
        resolver_builder: &mut ResolverBuilder,
        resolver_module: vector<u8>
    ) {
        resolver_builder.resolver_module = resolver_module;
    }

    public fun config_mut<Rule: drop, Config: store>(
        self: &mut Schema
    ): &mut Config {
        self.resolver.borrow_mut().config.borrow_mut(type_name::with_defining_ids<Rule>())
    }

    public fun approve<Rule: drop>(
        request: &mut Request,
        _: Rule
    ) {
        request.approvals.insert(type_name::with_defining_ids<Rule>());
    }
}