package Ado::Plugin::I18n;
use Mojo::Base 'Ado::Plugin';
use I18N::LangTags qw(implicate_supers);
use I18N::LangTags::Detect;
use List::Util qw(first);
use Time::Seconds;

#example.com/cz/foo/bar
sub routes {
    my $self   = shift;
    my $config = $self->config;
    return $$config{routes} if $$config{routes};
    return [] unless $$config{language_from_route};
    my $l = join '|', @{$$config{languages}};
    return $self->config->{routes} = [

#Language prefixed front-end controllers
        {   route  => '/:language',
            params => {$$config{language_param} => qr/(?:$l)/},
            via    => [qw(GET OPTIONS)],

            #Ado::Control::Default::index()
            to => 'default#index',
        },
        {   route  => '/:language/:controller',
            via    => [qw(GET OPTIONS)],
            params => {$$config{language_param} => qr/(?:$l)/},
            to     => {

                #Ado::Control::Default
                controller => 'Default',
                action     => 'index'
            }
        },
        {   route  => '/:language/:controller/:action',
            via    => [qw(GET POST OPTIONS)],
            params => {$$config{language_param} => qr/(?:$l)/},
            to     => {

                #Ado::Control::Default
                controller => 'Default',
                action     => 'index'
            }
        },
        {   route  => '/:language/:controller/:action/:id',
            via    => [qw(GET PUT DELETE OPTIONS)],
            params => {$$config{language_param} => qr/($l)/},
            to     => {

                #Ado::Control::Default
                controller => 'Default',
                action     => 'form'
            }
        },
    ];
}


sub register {
    my ($self, $app, $config) = @_;
    $self->app($app);    #!Needed in $self->config!

    #Merge passed configuration (usually from etc/ado.conf) with configuration
    #from  etc/plugins/markdown_renderer.conf
    $config = $self->{config} = {%{$self->config}, %{$config ? $config : {}}};
    $app->log->debug('Plugin ' . $self->name . ' configuration:' . $app->dumper($config));

    #Make sure we have all we need from config files.
    $config->{default_language} ||= 'en';

    #Supported languages by this system
    $config->{languages} ||= ['en', 'bg'];

    #Try to get language from these places in the order below
    $config->{language_from_route}   ||= 1;
    $config->{language_from_host}    ||= 1;
    $config->{language_from_param}   ||= 1;
    $config->{language_from_cookie}  ||= 1;
    $config->{language_from_headers} ||= 1;
    $config->{language_param}        ||= 'language';

    #Allow other namespaces too
    $config->{namespace} ||= 'Ado::I18n';

    my $e = Mojo::Loader->new->load($config->{namespace});
    $app->log->warn(qq{Loading "$config->{namespace}" failed: $e}) if $e;

    #Add helpers
    $app->helper(language => \&language);
    $app->helper(l        => \&_maketext);

    #default routes including language placeholder.
    $app->load_routes($self->routes);

    # Add hook around_action
    $app->hook(around_action => \&around_action);

    #make plugin configuration available for later in the app
    $app->config(__PACKAGE__, $config);
    return $self;
}

#Mojolicious::around_action hook.
sub around_action {
    local $_ = undef;
    my ($next, $c, $action, $last_step) = @_;
    $c->language();
    return $next->();
}

#sets *once* and/or returns the current language - a controller property
sub language {
    my ($c, $language) = @_;
    state $config  = $c->app->config(__PACKAGE__);
    state $l_param = $$config{language_param};
    my $stash = $c->stash;


    #language('fr') should be used in very
    #rare cases since it is called in around_action
    if ($language) {
        $stash->{i18n} =
          $$config{namespace}->get_handle($language, @{$$config{languages}});
        $c->debug("language('$language') explicitly set by developer");

        return $stash->{$l_param} = $language;
    }

    #already set from route or called in an action
    if ($stash->{$l_param}) {
        $stash->{i18n} ||=
          $$config{namespace}->get_handle($stash->{$l_param}, @{$$config{languages}});
        $c->debug("already set in \$stash->{$l_param}:" . $stash->{$l_param});
        return $stash->{$l_param};
    }

    #bg.example.com
    if ($$config{language_from_host}
        && (my ($l) = $c->req->headers->host =~ /^(\w{2})\./))
    {
        $stash->{i18n} =
          $$config{namespace}->get_handle($l, @{$$config{languages}});
        $c->debug("language_from_host:$l");
        return $stash->{$l_param} = $l;
    }

    #?language=de
    if ($$config{language_from_param}
        && (my $l = ($c->param($l_param) // '')))
    {
        $stash->{$l_param} = $l;
        $c->debug("language_from_param:$l_param:$stash->{$l_param}");
    }


    if (  !$stash->{language}
        && $$config{language_from_cookie}
        && ($language = $c->cookie($$config{language_param})))
    {
        $c->cookie($$config{language_param} => $language, {expires => time + ONE_MONTH});
        $stash->{$l_param} = $language;
        $c->debug("language_from_cookie:$stash->{$l_param}");
    }

    #Accept-Language:"bg,fr;q=0.8,en-us;q=0.5,en;q=0.3"
    elsif (!$stash->{$l_param} && $$config{language_from_headers}) {
        my @languages =
          I18N::LangTags::implicate_supers(
            I18N::LangTags::Detect->http_accept_langs($c->req->headers->accept_language));
        foreach my $l (@languages) {
            $stash->{$l_param} = first { $_ =~ /$l/ } @{$$config{languages}};
            last if $stash->{$l_param};
        }
        $c->debug("language_from_headers:$stash->{$l_param}") if $stash->{$l_param};
    }

    #default
    $stash->{$l_param} = $$config{default_language} unless $stash->{$l_param};


    $stash->{i18n} =
      $$config{namespace}->get_handle($stash->{$l_param}, @{$$config{languages}});
    return $stash->{$l_param};
}

sub _maketext {
    my ($c, $key) = (shift, shift);
    return ref($c->{stash}{i18n}) ? $c->{stash}{i18n}->maketext($key, @_) : $key;
}

1;

=pod

=encoding utf8

=head1 NAME

Ado::Plugin::I18n - Internationalization and localization for Ado

=head1 SYNOPSIS

This plugin just works. Nothing special needs to be done.

    #Override the current language.
    #you need to do this only in rare cases (like in an Ado::Command)
    $c->language('bg');
    #what is my language?
    my $current_language = $c->language;

=head1 DESCRIPTION

L<Ado::Plugin::I18n> localizes your application and site.
It altomatically detects the current UserAgent language preferences
and selects the best fit from the supported by the application languages.
The current language is deteted and set in L<Mojolicious/around_action> hook.
Various methods for setting the language are supported.

=head1 OPTIONS

The following options can be set in C<etc/ado.conf> or in C<etc/plugins/i18n.conf>.
You have to create first C<etc/plugins/i18n.conf> so Ado can pick it up.
You can enable all supported methods to detect the language in your application.

The methods which will be used to detect and set the current
language are as follows:

  1. language_from_route,   eg. /bg/controller/action
  2. language_from_host,    eg. fr.example.com
  3. language_from_param,   eg. ?language=de
  4. language_from_cookie,  eg. Cookie: language=bg;
  5. language_from_headers, eg. Accept-Language: bg,fr;q=0.8,en-us;q=0.5,en;q=0.3

Just be careful not to try to set the language in one request using two different
methods eg. C</bg/controller/action?language=de>. 


=head2 default_language

The default value is C<en>. This language is used when Ado is not able to detect
the language using any of the methods enabled by the options below.
If you want to set a different language be sure to create a language class
in your languages namespace. See also L</namespace>.

=head2 language_from_route

    {
        language_from_route => 1
        ...
    }

This is the first option that will be checked if enabled.
The plugin prepares a default set of routes containing information 
about the language.

  /:language                          GET,OPTIONS
  /:language/:controller              GET,OPTIONS
  /:language/:controller/:action      GET,POST,OPTIONS
  /:language/:controller/:action/:id  GET,PUT,DELETE,OPTIONS

The language will be detected from current routes eg. C</bg/news/read/1234>
and put into the stash. Default value is 1.

=head2 language_from_host

    {
        language_from_host => 1,
        language_from_route => 1,
        ...
    }

This is the second option that will be checked if enabled.
If you use languages as subdomains make sure to disable  C<language_from_route>
or do not construct routes containing languages (eg. C<fr.example.com/en>).
Default value is 1.

=head2 language_from_param

    {
        
        language_from_param => 1,
        language_from_host =>  0,
        language_from_route => 0,
        ...
    }

This is the third option that will be checked if enabled and if the language is
not yet detected using some of the previous methods.
Make sure to not construct urls like C<fr.example.com?language=de>
or even C<fr.example.com/bg?language=de>. The result is usually not what you want.
Default value is 1.

=head2 language_from_cookie

    {
        
        language_from_cookie => 1,
        language_from_param =>  1,
        language_from_host =>   0,
        language_from_route =>  0,
        ...
    }

This is the fourth option that will be checked if enabled and if the language is
not yet detected using some of the previous methods.
This option is most suitable for applications which expect to find a cookie
with name "language" and value one of the supported languages.
Default value is 1.

=head2 language_from_headers

    {
        
        language_from_headers => 1
        language_from_cookie  => 1,
        language_from_param   => 1,
        language_from_host    => 0,
        language_from_route   => 0,
        ...
    }

This is the fifth option that will be checked if enabled and if the language is
not yet detected using some of the previous methods.
It is best to keep this option enabled.
Default value is 1.

=head2 language_param

    #language_param=> 'l'
    current language is <%= $l %>
    Cookie: l=bg;
    #language_param=> 'lang'
    current language is <%= $lang %>
    Cookie: lang=bg;

The name of the parameter(key) used in C<language_from_param>, C<language_from_route>
and C<language_from_cookie>. this is also the key used in the C<$c-E<gt>stash>.
Default value is "language".

=head2 namespace

The namespace used for language classes.
Default value is L<Ado::I18n>.
You rarely will want to change this.

=head1 HELPERS

L<Ado::Plugin::I18n> exports the following helpers for use in  
L<Ado::Control> methods and templates.

=head2 language

Allows you to reset the current language. You do not need to use this helper
it is called automatically in L<Mojolicious/around_action> hook.

=head2 l

Same as L<Locale::Maketext/maketext>.

  $c->render(text => $c->l('hello', $c->user->name));
  <%= l('hello', user->name) %>

=head1 METHODS

L<Ado::Plugin::I18n> inherits all methods from
L<Ado::Plugin> and implements the following new ones.


=head2 register

This method is called by C<$app-E<gt>plugin>.
Registers the plugin in L<Ado> application and merges internationalization
and localization configuration from C<$MOJO_HOME/etc/ado.conf> with settings 
defined in C<$MOJO_HOME/etc/plugins/i18n.conf>. Authentication settings 
defined in C<ado.conf> will overwrite those defined in C<plugins/i18n.conf>.
Returns C<$self>.

=head2 routes

Returns a list of routes with C<:language> placeholder
defined in the plugin configuration. Called in L</register>.

  #default routes including language placeholder.
  $app->load_routes($self->routes);

  /:language                          GET,OPTIONS
  /:language/:controller              GET,OPTIONS
  /:language/:controller/:action      GET,POST,OPTIONS
  /:language/:controller/:action/:id  GET,PUT,DELETE,OPTIONS

=head2 language

This is the underlying subroutine used in C<around_action> hook and c<language>
helper.

    #Add helpers
    $app->helper(language => \&language);

=head2 around_action

This method is passed as reference to be used as L<Mojolicious/around_action>.

    # Add hook around_action
    $app->hook(around_action => \&around_action);

=head1 TODO

Create a table with message entries which will be loaded by this plugin.
Create user interface to add/edit entries.

=head1 SEE ALSO

L<Locale::Maketext>, L<Ado::Plugin>, L<Ado::Manual::Plugins>, 
L<Mojolicious::Plugins>, 
L<Mojolicious::Plugin>, L<Mojolicious::Guides::Routing/Conditions>

=head1 SPONSORS

The original author

=head1 AUTHOR

Красимир Беров (Krasimir Berov)

=head1 COPYRIGHT AND LICENSE

Copyright 2014 Красимир Беров (Krasimir Berov).

This program is free software, you can redistribute it and/or
modify it under the terms of the 
GNU Lesser General Public License v3 (LGPL-3.0).
You may copy, distribute and modify the software provided that 
modifications are open source. However, software that includes 
the license may release under a different license.

See http://opensource.org/licenses/lgpl-3.0.html for more information.

=cut