package Ado::Plugin::Auth;
use Mojo::Base 'Ado::Plugin';
sub _login_ado;

sub register {
    my ($self, $app, $config) = @_;
    $self->app($app);    #!Needed in $self->config!

    #Merge passed configuration (usually from etc/ado.conf) with configuration
    #from  etc/plugins/markdown_renderer.conf
    $config = $self->{config} = {%{$self->config}, %{$config ? $config : {}}};
    $app->log->debug('Plugin ' . $self->name . ' configuration:' . $app->dumper($config));

    #Make sure we have all we need from config files.
    $config->{auth_methods} ||= ['ado', 'facebook'];
    $app->config(auth_methods => $config->{auth_methods});

    # Add helpers
    $app->helper(
        'user' => sub {
            Ado::Model::Users->query("SELECT * from users WHERE login_name='guest'");
        }
    );
    $app->helper(login_ado => sub { _login_ado(@_) });

    #Load routes if they are passed
    push @{$app->renderer->classes}, __PACKAGE__;
    $app->load_routes($config->{routes})
      if (ref($config->{routes}) eq 'ARRAY' && scalar @{$config->{routes}});

    return $self;
}


# helper used in auth_ado
# authenticates the user and returns true/false
sub digest_auth {
    my $c = shift;

    return 0;
}

# general condition for authenticating users - dispatcher to specific authentication method
sub auth {
    my ($route, $c, $captures, $patterns) = @_;
    $c->debug($route, $c, $captures, $patterns);

    return 1;
}

# condition to locally authenticate a user
sub auth_ado {
    my ($route, $c, $captures, $patterns) = @_;


    return 1;
}


#condition to authenticate a user via facebook
sub auth_facebook {
    my ($route, $c, $captures, $patterns) = @_;


    return 1;
}

sub login {
    my ($c) = @_;
    return $c->render('login') if $c->req->method ne 'POST';
    my $auth_method = Mojo::Util::trim($c->param('auth_method'));
    $c->debug('param auth_method', $c->param('auth_method'));
    $c->debug('stash auth_method', $c->stash('auth_method'));


    #derive a helper name for login the user
    my $login_helper = 'login_' . $auth_method;
    my $authnticated = 0;
    if (eval { $authnticated = $c->$login_helper(); 1 }) {
        if ($authnticated) {

            # Store a friendly message for the next page in flash
            $c->flash(message => 'Thanks for logging in.');
            $c->debug($c->flash('message') . "\$authnticated:$authnticated");

            # Redirect to protected page with a 302 response
            return $c->redirect_to($c->session('over_route') || '/');
        }
        else {
            $c->stash(error_login => 'Wrong credentials! Please try again.');
            return $c->render('login');
        }
    }
    else {
        $c->app->log->error("Unknown \$login_helper:[$login_helper]");
        $c->flash(error => 'Please choose one of the supported login methods.');
        $c->redirect_to($c->session('over_route') || '/');
        return;
    }
    return;
}

#used as helper 'login_ado'
sub _login_ado {
    my ($c) = @_;
    $c->debug('param auth_method', $c->param('auth_method'));
    $c->debug('stash auth_method', $c->stash('auth_method'));
    return 0;
}
1;


=pod

=encoding utf8

=head1 NAME

Ado::Plugin::Auth - Authenticate users

=head1 SYNOPSIS

  #in ado.${\$app->mode}.conf
  plugins =>[
    #...
    {name => 'auth', config => {
        services =>['ado', 'facebook',...]
      }
    }
    #...
  ]

=head1 DESCRIPTION

L<Ado::Plugin::Auth> is a plugin that authenticates users to an L<Ado> system.
Users can be authenticated locally or using (TODO!) Facebook, Google, Twitter
and other authentication service-providers.

=head1 OPTIONS

The following options can be set in C<etc/ado.conf>.
You can find default options in C<etc/plugins/auth.conf>.

=head2 auth_methods

This option will enable the listed methods (services) which will be used to 
authenticate a user. The services will be listed in the specified order
in the partial template C<authbar.html.ep> that can be included
in any other template on your site.

  #in ado.${\$app->mode}.conf
  plugins =>[
    #...
    {name => 'auth', config => {
        services =>['ado', 'facebook',...]
      }
    }
    #...
  ]

=head1 CONDITIONS

L<Ado::Plugin::Auth> provides the following conditions to be used by routes.

=head2 auth

  #programatically
  $app->routes->route('/ado-users/:action', over => {auth => {ado => 1}});
  $app->routes->route('/ado-users/:action', over =>'auth');
  $app->routes->route('/ado-users/:action', over =>['auth','authz','foo','bar']);

  #in ado.conf or ado.${\$app->mode}.conf
  routes => [
    #...
    {
      route => '/ado-users/:action:id',
      via   => [qw(PUT DELETE)],
      
      # only local users can edit and delete users,
      # and only if they are authorized to do so
      over =>[auth => {ado => 1},'authz'],
      to =>'ado-users#edit'
    }
  ],

Condition for routes used to check if a user is authenticated.
Additional parameters can be passed to specify the preferred authentication method to be used
if condition redirects to C</login/:auth_method>.

=head2 auth_ado

Same as:

  auth => {ado => 1},

=head2 auth_facebook

Same as:

  auth => {facebook => 1},


=head1 HELPERS

L<Ado::Plugin::Auth> exports the following helpers for use in  
L<Ado::Control> methods and templates.

=head2 user

Returns the current user - C<guest> for not authenticated users.

  $c->user(Ado::Model::Users->query("SELECT * from users WHERE login_name='guest'"));
  my $current_user = $c->user;

=head2 digest_auth

The helper used in L</login> action to authenticate the user.

  if($c->digest_auth){
    #good, continue
  }
  else {
    $c->render(status=>401,text =>'401 Unauthorized')
  }

=head1 ROUTES

L<Ado::Plugin::Auth> provides the following routes (actions):

=head2 login

  /login/:auth_method

If accessed using a C<GET> request displays a login form.
If accessed via C<POST> performs authentication using C<:auth_method>.


=head1 METHODS

L<Ado::Plugin::Auth> inherits all methods from
L<Ado::Plugin> and implements the following new ones.


=head2 register

This method is called by C<$app-E<gt>plugin>.
Registers the plugin in L<Ado> application and merges authentication 
configuration from C<$MOJO_HOME/etc/ado.conf> with settings defined in
C<$MOJO_HOME/etc/plugins/auth.conf>. Authentication settings defined in C<ado.conf>
will overwrite those defined in C<plugins/auth.conf>.

=head1 TODO

The following authentication methods are in the TODO list:
facebook, linkedin, google.
Others may be added later.

=head1 SEE ALSO

L<Ado::Plugin>, L<Ado::Manual::Plugins>,L<Mojolicious::Plugins>, 
L<Mojolicious::Plugin>, 

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


__DATA__

@@ partials/authbar.html.ep
%# displayed as a menu item
<div class="right compact menu" id="authbar">
% if (user->login_name eq 'guest') {
  <div class="ui simple dropdown item">
  Login using<i class="dropdown icon"></i>
    <div class="menu">
    % for my $auth(@{app->config('auth_methods')}){
      <a href="<%=url_for("login/$auth")->to_abs %>" class="item">
        <i class="<%=$auth %> icon"></i> <%=ucfirst $auth %>
      </a>
    % }    
    </div>
  </div>
  <div class="ui small modal" id="modal_login_form">
    <i class="close icon"></i>
    %=include 'partials/login_form'
  </div><!-- end modal dialog with login form in it -->
% } else {
  <a href="logout"><i class="sign out icon"></i> <%=user->login_name %></a>
% }
</div>

@@ partials/login_form.html.ep
  <form class="ui form segment" method="POST" action="" id="login_form">
    <div class="ui header">
    % # Messages will be I18N-ed via JS or Perl on a per-case basis
      Login
    </div>
    % if(stash->{error_login}) {
    <div class="ui error message" style="display:block">
      <p><%= stash->{error_login} %></p>
    </div>
    % }
    <div class="field auth_methods">
      % for my $auth(@{app->config('auth_methods')}){
      <span class="ui toggle radio checkbox">
        <input name="_method" type="radio" id="<%=$auth %>_radio"
          %== (stash->{auth_method}//'') eq $auth ? 'checked="checked"' : ''
          value="<%=url_for('login/'.$auth) %>" />
        <label for="<%=$auth %>_radio">
          <i class="<%=$auth %> icon"></i><%=ucfirst $auth %>
        </label>
      </span>&nbsp;&nbsp;
      % }
    </div>
    <div class="field">
      <label for="login_name">Username</label>
      <div class="ui left labeled icon input">
        <input placeholder="Username" type="text" name="login_name" id="login_name" />
        <i class="user icon"></i>
        <div class="ui corner label"><i class="icon asterisk"></i></div>
      </div>
    </div>
    <div class="field">
      <label for="login_password">Password</label>
      <div class="ui left labeled icon input">
        <input type="password" name="login_password" id="login_password" />
        <i class="lock icon"></i>
        <div class="ui corner label"><i class="icon asterisk"></i></div>
      </div>
    </div>
    %= csrf_field
    <div class="ui center">
      <button class="ui small green submit button" type="submit">Login</button>
    </div>
  </form>
%= javascript '/js/auth.js'

@@ login.html.ep
% layout 'default';
<section class="ui login_form">
%= include 'partials/login_form'
</section>
