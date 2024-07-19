package Plack::App::Catmandu::SRU;

our $VERSION = '0.01';

use Catmandu::Sane;
use Catmandu;
use Catmandu::Fix;
use Catmandu::Exporter::Template;
use URI;
use SRU::Request;
use SRU::Response;
use Types::Standard qw(Str ArrayRef HashRef);
use Types::Common::String qw(NonEmptyStr);
use Types::Common::Numeric qw(PositiveInt);
use Moo;
use namespace::clean;
use feature qw(signatures);
no warnings qw(experimental::signatures);

has store_name => (
    is => 'ro',
    isa => Str,
    init_arg => 'store',
);

has bag_name => (
    is => 'ro',
    isa => Str,
    init_arg => 'bag',
);

has content_type => (
    is => 'ro',
    isa => Str,
    default => sub { 'text/xml'; },
);

has cql_filter => (
    is => 'ro',
    isa => NonEmptyStr,
);

has default_record_schema => (
    is => 'ro',
    isa => NonEmptyStr,
    required => 1,
);

has record_schemas => (
    is => 'ro',
    isa => ArrayRef[HashRef],
    default => sub { []; },
);

has title => (
    is => 'ro',
    isa => NonEmptyStr,
);

has description => (
    is => 'ro',
    isa => NonEmptyStr,
);

has template_options => (
    is => 'ro',
    isa => HashRef,
    default => sub { +{}; },
);

has default_search_params => (
    is => 'ro',
    isa => HashRef,
    default => sub { {}; },
);

has limit => (
    is => 'lazy',
    isa => PositiveInt,
);

has maximum_limit => (
    is => 'lazy',
    isa => PositiveInt,
);

has bag => (
    is => 'lazy',
    init_arg => undef,
);

sub _build_bag ($self) {
    Catmandu->store($self->store_name)->bag($self->bag_name);
}

sub _build_limit ($self) {
    $self->bag->default_limit;
}

sub _build_maximum_limit ($self) {
    $self->bag->maximum_limit;
}

sub to_app ($self) {
    my $default_limit   = $self->limit;
    my $maximum_limit   = $self->maximum_limit;
    my $template_options= $self->template_options;
    my $bag = $self->bag;

    my $record_schema_map = {};
    for my $schema (@{$self->record_schemas}) {
        $schema = {%$schema};
        my $identifier = $schema->{identifier};
        my $name = $schema->{name};
        if (my $fix = $schema->{fix}) {
            $schema->{fix} = Catmandu::Fix->new(fixes => $fix);
        }
        $record_schema_map->{$identifier} = $schema;
        $record_schema_map->{$name} = $schema;
    }

    my $database_info = "";
    if ($self->title || $self->description) {
        $database_info .= qq(<databaseInfo>\n);
        for my $key (qw(title description)) {
            $database_info .= qq(<$key lang="en" primary="true">).$self->$key.qq(</$key>\n) if $self->$key;
        }
        $database_info .= qq(</databaseInfo>);
    }

    my $index_info = "";
    if ($bag->can('cql_mapping') and my $indexes = $bag->cql_mapping->{indexes}) {
        $index_info .= qq(<indexInfo>\n);
        for my $key (keys %$indexes) {
            my $title = $indexes->{$key}{title} || $key;
            $index_info .= qq(<index><title>$title</title><map><name>$key</name></map></index>\n);
        }
        $index_info .= qq(</indexInfo>);
    }

    my $schema_info = qq(<schemaInfo>\n);
    for my $schema (@{ $self->record_schemas }) {
        my $title = $schema->{title} || $schema->{name};
        $schema_info .= qq(<schema name="$schema->{name}" identifier="$schema->{identifier}"><title>$title</title></schema>\n);
    }
    $schema_info .= qq(</schemaInfo>);

    my $config_info = qq(<configInfo>\n);
    $config_info .= qq(<default type="numberOfRecords">$default_limit</default>\n);
    $config_info .= qq(<setting type="maximumRecords">$maximum_limit</setting>\n);
    $config_info .= qq(</configInfo>);

    sub {
        my $env = $_[0];

        my $req = Plack::Request->new($env);

        return not_found() if $req->method() ne "GET";

        my $params      = $req->query_parameters();
        my $operation   = $params->get('operation') // 'explain';

        if ($operation eq 'explain') {
            my $request     = SRU::Request::Explain->new($params->flatten);
            my $response    = SRU::Response->newFromRequest($request);
            my $transport   = $req->scheme;
            my $uri         = URI->new($req->base().$req->request_uri);
            my $host        = $uri->host;
            my $port        = $uri->port;
            my $database    = (split(/\//o, $uri->path))[-1];
            $response->record(SRU::Response::Record->new(
                recordSchema => 'http://explain.z3950.org/dtd/2.0/',
                recordData   => <<XML,
<explain xmlns="http://explain.z3950.org/dtd/2.0/">
    <serverInfo protocol="SRU" transport="$transport">
    <host>$host</host>
    <port>$port</port>
    <database>$database</database>
    </serverInfo>
    $database_info
    $index_info
    $schema_info
    $config_info
</explain>
XML
            ));
            return $self->render_sru_response($response);
        }
        elsif ($operation eq 'searchRetrieve') {
            my $request  = SRU::Request::SearchRetrieve->new($params->flatten);
            my $response = SRU::Response->newFromRequest($request);
            if (@{$response->diagnostics}) {
                return $self->render_sru_response($response);
            }

            my $schema = $record_schema_map->{$request->recordSchema || $self->default_record_schema};
            unless ($schema) {
                $response->addDiagnostic(SRU::Response::Diagnostic->newFromCode(66));
                return $self->render_sru_response($response);
            }
            my $identifier  = $schema->{identifier};
            my $fix         = $schema->{fix};
            my $template    = $schema->{template};
            my $layout      = $schema->{layout};
            my $cql         = $params->get('query');
            if ($self->cql_filter) {
                # space before the filter is to circumvent a bug in the Solr
                # 3.6 edismax parser
                $cql = "( ".$self->cql_filter.") and ( $cql)";
            }

            my $first = $request->startRecord // 1;
            my $limit = $request->maximumRecords // $default_limit;
            if ($limit > $maximum_limit) {
                $limit = $maximum_limit;
            }

            my $hits = eval {
                $bag->search(
                    %{$self->default_search_params},
                    cql_query    => $cql,
                    sru_sortkeys => $request->sortKeys,
                    limit        => $limit,
                    start        => $first - 1,
                );
            } or do {
                my $e = $@;
                if (index($e, 'cql error') == 0) {
                    $response->addDiagnostic(SRU::Response::Diagnostic->newFromCode(10));
                    return $self->render_sru_response($response);
                }
                Catmandu::Error->throw($e);
            };

            $hits->each(sub {
                my $data     = $_[0];
                my $metadata = "";
                my $exporter = Catmandu::Exporter::Template->new(
                    %$template_options,
                    template => $template,
                    file     => \$metadata
                );
                $exporter->add($fix ? $fix->fix($data) : $data);
                $exporter->commit;
                $response->addRecord(SRU::Response::Record->new(
                    recordSchema => $identifier,
                    recordData   => $metadata,
                ));
            });
            $response->numberOfRecords($hits->total);
            return $self->render_sru_response($response);
        }
        else {
            my $request  = SRU::Request::Explain->new($params->flatten);
            my $response = SRU::Response->newFromRequest($request);
            $response->addDiagnostic(SRU::Response::Diagnostic->newFromCode(6));
            return $self->render_sru_response($response);
        }
    };
}

sub render_sru_response ($self, $response) {
    my $body = $response->asXML;
    utf8::encode($body);
    [200, ['Content-Type' => $self->content_type], [$body]];
}

sub not_found ($self) {
    [404, ['Content-Type' => 'text/plain'], ['not found']];
}

1;

=head1 DESCRIPTION

=head1 SYNOPSIS

    use Plack::Builder;
    Plack::App::Catmandu::SRU;

    builder {
        enable 'ReverseProxy';
        enable '+Dancer::Middleware::Rebase', base  => Catmandu->config->{uri_base}, strip => 1;
        mount "/sru" => Plack::App::Catmandu::SRU->new(
            store => 'search',
            bag   => 'publication',
            cql_filter => 'type = dataset',
            limit  => 100,
            maximum_limit => 500,
            record_schemas => [
                {
                    identifier => "info:srw/schema/1/mods-v3.6",
                    title => "MODS",
                    name => "mods_36",
                    template => "views/export/mods_36.tt",
                    fix => 'fixes/pub.fix'
                },
            ],
        )->to_app;
    };

=head1 CONFIGURATION

The configuration contains basic information for the Catmandu::SRU plugin to work:

    * store - In which Catmandu::Store are the metadata records stored
    * bag   - In which Catmandu::Bag are the records of this 'store' (use: 'data' as default)
    * cql_filter -  A CQL query to find all records in the database that should be made available to SRU
    * default_record_schema - The metadataSchema to present records in
    * limit - The maximum number of records to be returned in each SRU request
    * maximum_limit - The maximum number of search results to return
    * record_schemas - An array of all supported record schemas
        * identifier - The SRU identifier for the schema (see L<http://www.loc.gov/standards/sru/recordSchemas/>)
        * name - A short descriptive name for the schema
        * fix - Optionally an array of fixes to apply to the records before they are transformed into XML
        * template - The path to a Template Toolkit file to transform your records into this format
    * template_options - An optional hash of configuration options that will be passed to L<Catmandu::Exporter::Template> or L<Template>
    * content_type - Set a custom content type header, the default is C<text/xml>.
=cut
