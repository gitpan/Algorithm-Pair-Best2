#   Algorithm::Pair::Best2.pm
#
#   Copyright (C) 2004-2011 Reid Augustin reid@HelloSix.com
#
#   This library is free software; you can redistribute it and/or modify it
#   under the same terms as Perl itself, either Perl version 5.8.5 or, at your
#   option, any later version of Perl 5 you may have available.
#
#   This program is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
#   or FITNESS FOR A PARTICULAR PURPOSE.
#

use 5.002;
use strict;
use warnings;

package Algorithm::Pair::Best2;

our $VERSION = '2.035'; # VERSION

# ABSTRACT: select pairings (designed for Go tournaments, but can be used for anything).

use Carp;

sub new {
    my ($proto, %args) = @_;

    my $self = {};
    $self->{scoreSub} = delete $args{scoreSub}
                          || sub { croak "No scoreSub() callback" };
    $self->{items}    = delete $args{items}    || [];
    $self->{progress} = delete $args{progress} || sub { };
    $self->{window}   = delete $args{window}   || 5;
    if (keys %args) {
        croak sprintf "Unknown option%s to %s->new: %s",
                scalar(keys %args) > 1 ? 's' : '',
                __PACKAGE__,
                join(', ', keys %args);
    }
    return bless($self, ref($proto) || $proto);
}

sub add {

    push @{shift->{items}}, @_;
}

sub get_score {
    my ($self, $idx0, $idx1) = @_;

    my $cache_key = "$idx0,$idx1";
    if (not exists $self->{score_cache}{$cache_key}) {
        my $items = $self->{items};
        my $score = &{$self->{scoreSub}}($items->[$idx0], $items->[$idx1]);
        croak "Negative score: $score" if ($score < 0);
        $self->{score_cache}{$cache_key} = $score;
      # $self->{cache_misses}{$cache_key}++;
      # $self->{cache_misses_total}++;
    }
    else {
      # $self->{cache_hits}{$cache_key}++;
      # $self->{cache_hits_total}++;
    }
    return $self->{score_cache}{$cache_key};
}

sub pick {
    my ($self, $window) = @_;

    $window ||= $self->{window};    # size of sliding window

    my %paired;                     # for marking off pairs
    my @results;

    my $items = $self->{items};
    if (scalar(@{$items}) <= 0) {
        croak sprintf "No items";
    }
    if (scalar(@{$items}) & 1) {
        croak sprintf "Odd number of items (%d)", scalar @{$items};
    }
    my $progress = $self->{progress};

    # Sliding window:
    while (1) {
        # create new list containing only a windows-worth of items
        my @w_idxs;        # items for this window
        for my $idx (0 .. $#{$items}) {
            if (not exists $paired{$idx}) {
                push @w_idxs, $idx;
                last if (@w_idxs >= $window * 2) # window filled
            }
        }
        my $score = 0;  # need an initial score, might as well count
                        #   initial items as passed to us
        foreach (my $idx = 0; $idx < @w_idxs; $idx += 2) {
            $score += $self->get_score($w_idxs[$idx], $w_idxs[$idx + 1]);
        }
        # pair this window
        $self->_r_best(0, $score, \@w_idxs);

        if (scalar keys %paired < (scalar(@{$items}) - (2 * $window))) {
            # keep top pair
            $paired{$w_idxs[0]} = 1;
            $paired{$w_idxs[1]} = 1;
            push @results, $items->[$w_idxs[0]], $items->[$w_idxs[1]];
            &$progress($items->[$w_idxs[0]], $items->[$w_idxs[1]]);
        }
        else {
            # keep all the results, we are done
            push @results, map {$items->[$_]} @w_idxs;
            foreach (my $idx = 0; $idx < @w_idxs; $idx += 2) {
                &$progress($items->[$w_idxs[$idx]], $items->[$w_idxs[$idx + 1]]);
            }
            last;
        }
    }
  # print "cache hits:\n";
  # map { print "  $_:$self->{cache_hits}{$_}\n" } sort keys %{$self->{cache_hits}};
  # print "total misses: $self->{cache_misses_total}, hits: $self->{cache_hits_total}\n";
    return wantarray ? @results : \@results;
}

sub _r_best {
    my ($self, $depth, $best_score, $idxs) = @_;

    my $items = $self->{items};
    if (@{$idxs} <= 2) {
        croak sprintf("%d items left", scalar @{$idxs}) if (@{$idxs} <= 1);
        return $self->get_score($idxs->[0], $idxs->[1]);
    }
    my $best_trial;
    # starting at idx=1, move item at idx to slot 1, calculate scores
    for (my $idx = 0; $idx <= @{$idxs} - 2; $idx++) {
        my ($trial_0, $trial_1, @tail) = @{$idxs};  # copy of original
        if ($idx > 0) { # first is same as original
            # put second item at head of tail
            unshift @tail, $trial_1;
            # put the item from $idx in $tail into second item
            $trial_1 = splice @tail, $idx, 1;
        }
        # print "$idx trial [", join (', ', $trial_0, $trial_1, @tail), "]\n" if ($depth == 0);
        my $trial_score = $self->get_score($trial_0, $trial_1);   # first pair
        croak "Negative score: $trial_score" if ($trial_score < 0);
        next if ($trial_score >= $best_score);  # worse? abandon branch
        # get best pairing for tail and add to score
        $trial_score += $self->_r_best($depth + 1, $best_score, \@tail);
        next if ($trial_score >= $best_score);  # worse? abandon branch
        # aha, a potential candidate, save it
        $best_score = $trial_score;
        unshift @tail, $trial_0, $trial_1;
        $best_trial = \@tail;
        # print "$depth $idx Best    score=$best_score, idxs=[", $self->print_items(@{$best_trial}), "]\n" if ($depth == 0);
    }
    if ($best_trial) {
        @{$idxs} = @{$best_trial};
        # print "$depth   Improve score=$best_score, idxs=[", $self->print_items(@{$best_trial}), "]\n";
    }
    return $best_score;
}

sub print_items {
    my ($self, @idxs) = @_;

    return join ', ', map { $self->{items}[$_] } @idxs;
}

1;



=pod

=head1 NAME

Algorithm::Pair::Best2 - select pairings (designed for Go tournaments, but can be used for anything).

=head1 VERSION

version 2.035

=head1 SYNOPSIS

    use Algorithm::Pair::Best2;

    my $pair = Algorithm::Pair::Best2->new( [ options ] );

    $pair->add( item, [ item, ... ] );

    @new_pairs = $pair->pick( [ window ] );

=head1 DESCRIPTION

This is a re-write of Algorithm::Pair::Best.  The interface is simplified
and the implementation is significantly streamlined.

After creating an Algorithm::Pair::Best2 object (with -E<gt>B<new>), B<add>
items to the list of items (i.e: players) to be paired.  The final list
must contain an even number of items or B<pick>ing the pairs will throw an
exception.

Algorithm::Pair::Best2-E<gt>B<pick> explores all combinations of items and
returns the pairing list with the best (lowest) score.  This can be an
expensive proposition - the number of combinations goes up very fast with
respect to the number of items:

    items combinations
      2         1       (1)
      4         3       (1 * 3)
      6        15       (1 * 3 * 5)
      8       105       (1 * 3 * 5 * 7)
     10       945       (1 * 3 * 5 * 7 * 9
     12     10395       (1 * 3 * 5 * 7 * 9 * 11)
     14    135135       (1 * 3 * 5 * 7 * 9 * 11 * 13)

It is clearly unreasonable to try to pair a significant number of items.
Trying to completely pair even 30 items would take too long.

Fortunately, there is a way to get pretty good results for big lists,
even if they're not perfect.  Instead of trying to pair the whole list
at once, Algorithm::Pair::Best2 pairs a series of smaller groups in a
sliding window to get good 'local' results.

The B<-E<gt>new> method accepts a B<window> option to limit the number
of pairs in the sliding window.  The B<window> option can also be
overridden by calling B<pick> with an explicit window argument:

    $pair->pick($window);

The list should be at least partially sorted so that reasonable
pairing candidates are within the 'sliding window' of each other.
Otherwise the final results may not be globally 'best', but only
locally good.  For (e.g.) a tournament, sorting by rank is sufficient.

Here's how a window value of 5 works:  the best list for items 1
through 10 (5 pairs) is found.  Save the pairing for the top two items
and then slide the window down to pair items 2 through 12.  Save the
top pairing from this result and slide down again to items 4 through
14.  Keep sliding the window down until we reach the last 10 items
(which are completed in one iteration).  In this way, a large number
of pairings can be completed without taking factorial time.

=head1 METHODS

=over

=item my $pair = B<Algorithm::Pair::Best2-E<gt>new>( options )

Creates a B<new> Algorithm::Pair::Best2 object.

=item $pair-E<gt>B<add> ( item, [ item, ...] )

Add an item (or several items) to be paired.  Item(s) can be any scalar
or reference.  They will be passed (a pair at a time) to the B<scoreSub>
callback.

=item @new_pairs = $pair-E<gt>B<pick> ( ?$window? )

Returns the best pairing found using the sliding window technique as
discussed in DESCRIPTION above.  B<window> is the number of pairs in the
sliding window.  If no B<window> argument is passed, the B<window> selected
in the B<new>, or the default value is used.

B<pick> returns the list (or a reference to the list in scalar context) of
items in pairing order: new_pair[0] is paired to new_pair[1], new_pair[2]
to new_pair[3], etc.

If the number of items in the list (from B<add>) is not even, an exception
is thrown.

=back

=head1 OPTIONS

The B<-E<gt>new> method accepts the following options:

=over 4

=item B<window> => number of pairs

Sets the default number of pairs in the sliding window during B<pick>.  Can
also be set by passing a B<window> argument to B<pick>.

Default: 5

=item B<scoreSub> => reference to scoring callback

The callback is called as B<scoreSub>(item_0, item_1), where item_0 and item_1
are members of the list created by B<add>ing items.  The callback must
return a positive number representing the 'badness' of this pairing.  A
good pairing should have a number closer to 0 than a worse pairing.  If
B<scoreSub> returns a negative number, an exception is thrown.

B<scoreSub>(A, B) should be equal to B<scoreSub>(B, A).  B<scoreSub>(A, B)
is called only one time (for any particular A and B), and the result is
cached.  B<scoreSub>(B, A) is never called.

Note that scores are always positive (Algorithm::Pair::Best2 searches for
the lowest combined score).

Default: a subroutine that throws an exception.

=item B<progress> => reference to progress callback

Each time a pair is finalized in the B<pick> routine, the
B<progress>($item_0, $item_1) callback is called where $item_0 and
$item_1 are the most recently finalized pair:

  progress => sub {
    my ($item_0, $item_1) = @_;
    # assuming $items have a 'name' method that returns a string:
    print $item_0->name, " paired with ", $item_1->name, "\n";
  },

Default: a subroutine that does nothing.

=back

=head1 EXAMPLE

  use Scalar::Util qw( refaddr );
  use Algorithm::Pair::Best2;

  my @players = (
        Player->new(        # Player object defined elsewhere
            name => "Player 1",
            rank => 3.5,    # Player also has a 'rank' method
        ),
        Player->new( ... ), # more players
        ...
    );

  # some extra information not provided by Player methods:
  my %already_been_paired = (
    refaddr($player_0) => {
      refaddr($player_1) => 1,  # player_0 played player_1
      refaddr($player_4) => 1,  #   and player_4
    },
    ...
  );

  my $pair = Algorithm::Pair::Best2->new(
    scoreSub => sub {       # score callback
      my ($player_A, $player_B) = @_;

      # Compare using the 'rating' method defined for Players.
      # Closer in rating is a better match:
      my $score = abs($player_A->rating - $player_B->rating);

      ...

      # but if they have already been matched,  increase the 'badness' of
      # this pair by a lot:
      if ($already_been_paired{refaddr($player_A)}{refaddr($player_B)}) {
        $score += 50;
      }

      ...   # other criterion that can increase $score

      return $score;   # always positive
    }
  );

  $pair->add(sort { $a->rank <=> $b->rank } @players);

  my @pairs = $pair->pick;

  ...

=head1 SEE ALSO

=over

=item Games::Go::W3Gtd::Paring.pm

=back

=head1 AUTHOR

Reid Augustin <reid@hellosix.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Reid Augustin.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

