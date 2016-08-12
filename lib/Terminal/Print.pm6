unit class Terminal::Print;

use Terminal::Print::Grid2;

has $!current-buffer;
has Terminal::Print::Grid2 $.current-grid;

has @!buffers;
has Terminal::Print::Grid2 @.grids;

has @.grid-indices;
has %!grid-name-map;

has $.columns;
has $.rows;

use Terminal::Print::Commands;

constant T = Terminal::Print::Commands;

subset Valid::X of Int is export where * < %T::attributes<columns>;
subset Valid::Y of Int is export where * < %T::attributes<rows>;
subset Valid::Char of Str is export where *.chars == 1;

has Terminal::Print::MoveCursorProfile $.cursor-profile;
has &.move-cursor;

method new( :$cursor-profile = 'ansi' ) {
    my $columns   = +%T::attributes<columns>;
    my $rows      = +%T::attributes<rows>;
    my &move-cursor = %T::human-commands<move-cursor>{$cursor-profile};

    my $grid = Terminal::Print::Grid2.new( :$columns, :$rows );
    my @grid-indices = $grid.grid-indices;

    self!bind-buffer( $grid, my $buffer = [] );

    self.bless(
                :$columns, :$rows, :@grid-indices,
                :$cursor-profile, :&move-cursor,
                    current-grid    => $grid,
                    current-buffer  => $buffer
              );
}

submethod BUILD( :$current-grid, :$current-buffer, :$!columns, :$!rows, :@grid-indices, :$!cursor-profile ) {
    push @!buffers, $current-buffer;
    push @!grids, $current-grid;

    $!current-grid   := @!grids[0];
    $!current-buffer := @!buffers[0];

    @!grid-indices = @grid-indices;  # TODO: bind this to @!grids[0].grid-indices?
}

method !bind-buffer( $grid, $new-buffer is rw ) {
    for $grid.grid-indices -> [$x,$y] {
        $new-buffer[$x + ($y * $grid.rows)] := $grid[$x][$y];
    }
}

method add-grid( $name?, :$new-grid = Terminal::Print::Grid2.new( :$!columns, :$!rows ) ) {
    self!bind-buffer( $new-grid, my $new-buffer = [] );

    push @!grids, $new-grid;
    push @!buffers, $new-buffer;

    if $name {
        %!grid-name-map{$name} = +@!grids-1;
    }
    $new-grid;
}

method blit( $grid-identifier = 0 ) {
    self.clear-screen;
    self.print-grid($grid-identifier);
}

# 'clear' will also work through the FALLBACK
method clear-screen {
    print-command <clear>;
}

method initialize-screen {
    print-command <save-screen>;
    self.hide-cursor;
    self.clear-screen;
}

method shutdown-screen {
    self.clear-screen;
    # @!grids>>.shutdown;
    print-command <restore-screen>;
    self.show-cursor;
}

method print-command( $command ) {
    print-command($command, $!cursor-profile);
}

# AT-POS hands back a Terminal::Print::Column
#   $b[$x]
# Because we have AT-POS on the column object as well,
# we get
#   $b[$x][$y]
#
# TODO: implement $!current-grid switching
method AT-POS( $column-idx ) {
    $!current-grid.grid[ $column-idx ];
}

# AT-KEY returns the Terminal::Print::Grid.grid of whichever the key specifies
#   $b<specific-grid>[$x][$y]
method AT-KEY( $grid-identifier ) {
    self.grid( $grid-identifier );
}


multi method FALLBACK( Str $command-name where { %T::human-command-names{$_} } ) {
    print-command( $command-name );
}



# multi method sugar:
#    @!grids and @!buffers can both be accessed by index or name (if it has
#    one). The name is optionally supplied when calling .add-grid.
#
#    In the case of @!grids, we pass back the grid array directly from the
#    Terminal::Print::Grid object, actually notching both DWIM and DRY in one swoosh.
#    because you can do things like  $b.grid("background")[42][42] this way.
multi method grid( Int $index ) {
    @!grids[$index].grid;
}

multi method grid( Str $name ) {
    die "No grid has been named $name" unless my $grid-index = %!grid-name-map{$name};
    @!grids[$grid-index].grid;
}

#### grid-object stuff

#   Sometimes you simply want the object back (for stringification, or
#   introspection on things like column-range)
multi method grid-object( Int $index ) {
    @!grids[$index];
}

multi method grid-object( Str $name ) {
    die "No grid has been named $name" unless my $grid-index = %!grid-name-map{$name};
    @!grids[$grid-index];
}

multi method print-cell( Int $x, Int $y ) {
    # $!current-grid.print-cell($x,$y);
    print "{&!move-cursor($x, $y)}{$!current-grid.grid[$x][$y]}";
}

# TODO: provide reasonable constraint?
#   where *.comb == 1 means that you can't add escape chars
#   of any kind before sending to print-cell. but maybe that's
#   not such a bad thing?
# multi method print-cell( Int $x, Int $y, Str $c ) {
#     $!current-grid.print-cell($x,$y,$c);
# }

method change-cell( Int $x, Int $y, Str $c ) {
    $!current-grid.grid[$x][$y] = $c;
}
#### buffer stuff

multi method buffer( Int $index ) {
    @!buffers[$index];
}

multi method buffer( Str $name ) {
    die "No buffer has been named $name" unless my $buffer-index = %!grid-name-map{$name};
    @!buffers[$buffer-index];
}

#### print-grid stuff

multi method print-grid( Int $index ) {
    @!grids[$index].print-grid;
}

multi method print-grid( Str $name ) {
    die "No grid has been named $name" unless my $grid-index = %!grid-name-map{$name};
    @!grids[$grid-index].print-grid;
}

method !clone-grid-index( $origin, $dest? ) {
    my $new-grid;
    if $dest {
        $new-grid := self.add-grid($dest, new-grid => @!grids[$origin].clone);
    } else {
        @!grids.push: @!grids[$origin].clone;
    }
    return $new-grid;
}

#### clone-grid stuff

multi method clone-grid( Int $origin, Str $dest? ) {
    die "Invalid grid '$origin'" unless @!grids[$origin]:exists;
    self!clone-grid-index($origin, $dest);
}

multi method clone-grid( Str $origin, Str $dest? ) {
    die "Invalid grid '$origin'" unless my $grid-index = %!grid-name-map{$origin};
    self!clone-grid-index($grid-index, $dest);
}

#### range stuffs
#
# TODO: add hooks to dynamically bind $!current-grid to @!grids

method column-range {
    $!current-grid.column-range; # TODO: we can make the grids reflect specific subsets of these ranges
}

method row-range {
    $!current-grid.row-range;
}

method Str {
    ~$!current-grid;
}


=begin pod
=title Terminal::Print

=head1 Synopsis

L<Terminal::Print> implements an abstraction layer for printing characters to terminal
screens. The idea is to provide all the necessary mechanical details while leaving the actual
so called 'TUI' abstractions to higher level libraries.

This is/will be done by achieving two technical goals: a) multiple grid objects
which may be swapped in place, allowing for behind the sccene and b) allow any
code at any time to print async to the screen. I say 'is/will be' because
objective 'a' is finished, including both named and positional access.

    $t.grid(0);  # first grid, comes free
    $t.add-grid('home'); # create a second grid named 'home'
    $t.grid('home');     # or $t.grid(1)

'b' is also working! Most of the scripts in C<examples/> run async!

Obvious applications include snake clones, rogue engines and golfed art works :)

Oh, and Serious Monitoring Apps, of course.

=head1 Usage

In general an application will have only one L<Terminal::Print> object at a
time. This object can <L|.initialize-screen>, which stores the current state of
the terminal window and replaces it with a blank canvas.

TODO: Write more. For now please check out C<examples/show-love.p6> and
C<examples/zig-zag.p6> for usage examples. C<zig-zag> has an async invocation commented
out above the current 'main' line of the program.

=head1 Miscellany

=head2 Where are we at now?

All the features you can observe while running C<perl6 t/basics.t> work using
the new react/supply based L<Terminal::Print::Grid>. If you run that test file,
you will notice that C<Terminal::Print> is needing a better test harness.
Part of that is getting a C<STDERR> or some such pipe going, and printing state/
That will make debugging a lot easier.

Testing a thing that is primarily designed to print to a screen seems a bit
difficult anyway. I almost think we should make it interactive. 'Did you see a
screen of hearts?'

So: async (as mentioned above), testing, and debugging are current pain points.
Contributions welcome.

=head2 Why not just use L<NativeCall> and C<ncurses>?

I tried that first and it wasn't any fun. C<ncurses> unicode support is
admirable considering the age and complexity of the library, but it
still feels bolted on.

C<ncurses> is not re-entrant, either, which would nix one of the main benefits
we might be able to get from using Perl 6 -- easy async abstractions.

=head2 A note on buffers

C<buffer> was designed to provide a flat access mechanism: the first cell is
at 0 and the last cell is at *-1.

It's not currently in the test suite and I wonder if it is actually necessary.
If we do keep it we should move it to Terminal::Print::Grid.

=end pod
