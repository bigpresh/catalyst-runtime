package Catalyst::ActionChain;

use Moose;
extends qw(Catalyst::Action);

has chain => (is => 'rw');
has _current_chain_actions => (is=>'rw', init_arg=>undef, predicate=>'_has_current_chain_actions');
has _chain_last_action => (is=>'rw', init_arg=>undef, predicate=>'_has_chain_last_action', clearer=>'_clear_chain_last_action');
has _chain_captures => (is=>'rw', init_arg=>undef);
has _chain_original_args => (is=>'rw', init_arg=>undef, clearer=>'_clear_chain_original_args');
has _chain_next_args => (is=>'rw', init_arg=>undef, predicate=>'_has_chain_next_args', clearer=>'_clear_chain_next_args');
has _context => (is => 'rw', weak_ref => 1);

no Moose;

=head1 NAME

Catalyst::ActionChain - Chain of Catalyst Actions

=head1 SYNOPSIS

See L<Catalyst::Manual::Intro> for more info about Chained actions.

=head1 DESCRIPTION

This class represents a chain of Catalyst Actions. It behaves exactly like
the action at the *end* of the chain except on dispatch it will execute all
the actions in the chain in order.

=cut

sub dispatch {
    my ( $self, $c ) = @_;
    my @captures = @{$c->req->captures||[]};
    my @chain = @{ $self->chain };
    my $last = pop(@chain);

    $self->_current_chain_actions(\@chain);
    $self->_chain_last_action($last);
    $self->_chain_captures(\@captures);
    $self->_chain_original_args($c->request->{arguments});
    $self->_context($c);
    $self->_dispatch_chain_actions($c);
}

sub next {
    my ($self, @args) = @_;
    my $ctx = $self->_context;

    if($self->_has_chain_last_action) {
        @args ? $self->_chain_next_args(\@args) : $self->_chain_next_args([]);
        $self->_dispatch_chain_actions($ctx);
    } else {
        $ctx->action->chain->[-1]->next($ctx, @args) if $ctx->action->chain->[-1]->can('next');
    }

    return $ctx->last_action_state if $ctx->has_last_action_state;
}

sub _dispatch_chain_actions {
    my ($self, $c) = @_;
    while( @{$self->_current_chain_actions||[]}) {
        $self->_dispatch_chain_action($c);
        return if $self->_abort_needed($c);        
    }
    if($self->_has_chain_last_action) {
        $c->request->{arguments} = $self->_chain_original_args;
        $self->_clear_chain_original_args;
        unshift @{$c->request->{arguments}}, @{ $self->_chain_next_args} if $self->_has_chain_next_args;
        $self->_clear_chain_next_args;
        my $last_action = $self->_chain_last_action;
        $self->_clear_chain_last_action;
        $last_action->dispatch($c);
    }
}

sub _dispatch_chain_action {
    my ($self, $c) = @_;
    my ($action, @remaining_actions) = @{ $self->_current_chain_actions||[] };
    $self->_current_chain_actions(\@remaining_actions);
    my @args;
    if (my $cap = $action->number_of_captures) {
        @args = splice(@{ $self->_chain_captures||[] }, 0, $cap);
    }
    unshift @args, @{ $self->_chain_next_args} if $self->_has_chain_next_args;
    $self->_clear_chain_next_args;
    local $c->request->{arguments} = \@args;
    $action->dispatch( $c );
}

sub _abort_needed {
    my ($self, $c) = @_;
    my $abort = defined($c->config->{abort_chain_on_error_fix}) ? $c->config->{abort_chain_on_error_fix} : 1;
    return 1 if ($c->has_errors && $abort); 
}

sub from_chain {
    my ( $self, $actions ) = @_;
    my $final = $actions->[-1];
    return $self->new({ %$final, chain => $actions });
}

sub number_of_captures {
    my ( $self ) = @_;
    my $chain = $self->chain;
    my $captures = 0;

    $captures += $_->number_of_captures for @$chain;
    return $captures;
}

sub match_captures {
  my ($self, $c, $captures) = @_;
  my @captures = @{$captures||[]};

  foreach my $link(@{$self->chain}) {
    my @local_captures = splice @captures,0,$link->number_of_captures;
    return unless $link->match_captures($c, \@local_captures);
  }
  return 1;
}
sub match_captures_constraints {
  my ($self, $c, $captures) = @_;
  my @captures = @{$captures||[]};

  foreach my $link(@{$self->chain}) {
    my @local_captures = splice @captures,0,$link->number_of_captures;
    next unless $link->has_captures_constraints;
    return unless $link->match_captures_constraints($c, \@local_captures);
  }
  return 1;
}

# the scheme defined at the end of the chain is the one we use
# but warn if too many.

sub scheme {
  my $self = shift;
  my @chain = @{ $self->chain };
  my ($scheme, @more) = map {
    exists $_->attributes->{Scheme} ? $_->attributes->{Scheme}[0] : ();
  } reverse @chain;

  warn "$self is a chain with two many Scheme attributes (only one is allowed)"
    if @more;

  return $scheme;
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 METHODS

=head2 chain

Accessor for the action chain; will be an arrayref of the Catalyst::Action
objects encapsulated by this chain.

=head2 dispatch( $c )

Dispatch this action chain against a context; will dispatch the encapsulated
actions in order.

=head2 from_chain( \@actions )

Takes a list of Catalyst::Action objects and constructs and returns a
Catalyst::ActionChain object representing a chain of these actions

=head2 number_of_captures

Returns the total number of captures for the entire chain of actions.

=head2 match_captures

Match all the captures that this chain encloses, if any.

=head2 scheme

Any defined scheme for the actionchain

=head2 meta

Provided by Moose

=head1 AUTHORS

Catalyst Contributors, see Catalyst.pm

=head1 COPYRIGHT

This library is free software. You can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
