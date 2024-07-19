# NAME

Plack::App::Catmandu::SRU - drop in replacement for Dancer::Plugin::Catmandu::SRU

# SYNOPSIS

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

# CONSTRUCTOR ARGUMENTS

- store

    Name of Catmandu store in your catmandu store configuration

    Default: `default`

- bag

    Name of Catmandu bag in your catmandu store configuration

    Default: `data`

    This must be a bag that implements [Catmandu::CQLSearchable](https://metacpan.org/pod/Catmandu%3A%3ACQLSearchable), and that configures a `cql_mapping`

- cql\_filter

    A CQL query to find all records in the database that should be made available to SRU

- default\_record\_schema

    default metadata schema all records are shown in, when SRU parameter `recordSchema` is not gi en . Should be one listed in `record_schemas`

- limit

    The default number of records to be returned in each SRU request, when SRU parameter `maximumRecords` is not given during a searchRetrieve request.

    When not provided in the constructor, it is derived from the default limit of your catmandu bag (see [Catmandu::Searchable#default\_limit](https://metacpan.org/pod/Catmandu%3A%3ASearchable%23default_limit))

- maximum\_limit

    The maximum value allowed for request parameter `maximumRecords`.

    When not provided in the constructor, it is derived from the maximum limit of your catmandu bag (see [Catmandu::Searchable#maximum\_limit](https://metacpan.org/pod/Catmandu%3A%3ASearchable%23maximum_limit))

- record\_schemas

    An array of all supported record schemas. Each item in the array is an object with attributes:

    \* identifier - The SRU identifier for the schema (see [http://www.loc.gov/standards/sru/recordSchemas/](http://www.loc.gov/standards/sru/recordSchemas/))

    \* name - A short descriptive name for the schema

    \* fix - Optionally an array of fixes to apply to the records before they are transformed into XML

    \* template - The path to a Template Toolkit file to transform your records into this format

- template\_options

    An optional hash of configuration options that will be passed to [Catmandu::Exporter::Template](https://metacpan.org/pod/Catmandu%3A%3AExporter%3A%3ATemplate) or [Template](https://metacpan.org/pod/Template)

- content\_type

    Set a custom content type header, the default is `text/xml`.

- title

    Title shown in databaseInfo

- description

    Description shown in databaseInfo

- default\_search\_params

    Extra search parameters added during search in your catmandu bag:

        $bag->search(
            %{$self->default_search_params},
            cql_query    => $cql,
            sru_sortkeys => $request->sortKeys,
            limit        => $limit,
            start        => $first - 1,
        );

    Must be a hash reference

    Note that search parameter `cql_query`, `sru_sortkeys`, `limit` and `start` are overwritten

As this is meant as a drop in replacement for [Dancer::Plugin::Catmandu::SRU](https://metacpan.org/pod/Dancer%3A%3APlugin%3A%3ACatmandu%3A%3ASRU) all arguments should be the same.

So all arguments can be taken from your previous dancer plugin configuration, if necessary:

    use Dancer;
    use Catmandu;
    use Plack::Builder;
    use Plack::App::Catmandu::SRU;

    my $dancer_app = sub {
        Dancer->dance(Dancer::Request->new(env => $_[0]));
    };

    builder {
        enable 'ReverseProxy';
        enable '+Dancer::Middleware::Rebase', base  => Catmandu->config->{uri_base}, strip => 1;
    
        mount "/sru" => Plack::App::Catmandu::SRU->new(
            %{config->{plugins}->{'Catmandu::SRU'}}
        )->to_app;

        mount "/" => builder {
            # only create session cookies for dancer application
            enable "Session";
            mount '/' => $dancer_app;
        };
    };

# METHODS

- to\_app

    returns Plack application that can be mounted. Path rebasements are taken into account

# AUTHOR

- Nicolas Franck, `<nicolas.franck at ugent.be>`

# IMPORTANT

This module is still a work in progress, and needs further testing before using it in a production system

# LICENSE AND COPYRIGHT

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
