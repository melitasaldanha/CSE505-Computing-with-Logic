:- module(main, [
                        main/0,
                        main/1,
                        debugmain/1
                     ]).

/** <module> s(ASP) Ungrounded Stable Models Solver

Read in a normal logic program. Compute dual rules and the NMR check. Execute
the modified program according to the stable model semantics and output the
results.

@author Kyle Marple
@version 20170127
@license BSD-3
*/

/*
* Copyright (c) 2016, University of Texas at Dallas
* All rights reserved.
*  
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are met:
*     * Redistributions of source code must retain the above copyright
*       notice, this list of conditions and the following disclaimer.
*     * Redistributions in binary form must reproduce the above copyright
*       notice, this list of conditions and the following disclaimer in the
*       documentation and/or other materials provided with the distribution.
*     * Neither the name of the University of Texas at Dallas nor the
*       names of its contributors may be used to endorse or promote products
*       derived from this software without specific prior written permission.
*  
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
* AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
* IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
* DISCLAIMED. IN NO EVENT SHALL THE UNIVERSITY OF TEXAS AT DALLAS BE LIABLE FOR
* ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
* LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
* ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

:- use_module(library(lists)).
:- use_module(common).
:- use_module(comp_duals).
%:- use_module(debug).
:- use_module(interactive). % for help output
:- use_module(io).
:- use_module(nmr_check).
:- use_module(options).
:- use_module(program). % for destroy_program/0
:- use_module(solve).

%! main
% Used by compiled executable. Not for interactive runs.
main :-
        %time(submain),
        submain,
        halt.
main :-
        halt(1).

%! submain
% Original contents of the first clause of main/0. Split to allow the call to
% submain to be wrapped in main/0, ex. with time/1 or profile/1.
submain :-
        once(parse_args(Sources)),
        main2(Sources).

%! main(+Source:filepath)
% Wrapper for interactive runs.
%
% @param Source Path of input file, or list of paths for multiple files.
main(Sources) :-
        Sources = [_ | _],
        !, % list of input files
        main2(Sources).
main(Source) :-
        !, % single input file
        main2([Source]).

%! debugmain(+Args:list)
% Simulate calling from command line by passing the command line args as a list
% of strings. For debugging using the Prolog console.
% Ex. debugmain(['-vv','-nf','file.asp']).
%
% @param Args The list of commandline arguments, including input files.
debugmain(Args) :-
        once(parse_args2(Args, Sources)),
        main2(Sources).

%! main2(+Sources:list)
% Output of each call should be deterministic, so backtracking is not necessary
% at this level.
%
% @param Sources A list of paths of input files.
main2(_) :-
        user_option(help, 1),
        !,
        help.
main2([]) :- % require an input file
        write(user_error, 'ERROR: No input file specified!\n\n'),
        help,
        !.
main2(Sources) :-
        once(set_stack_sizes),
        once(set_default_options),
        once(load_source_files(Sources)),
        once(comp_duals),
        once(generate_nmr_check),
        write_verbose(0, 'Preparation of input program complete.\n'),
        user_option(mode, Mode),
        once(solve(Mode)),
        destroy_program,
        option_cleanup.

%! parse_args(-Sources:list)
% Handle command-line arguments. Strip first entry.
%
% @param Sources Paths of input files.
parse_args(Sources) :-
        current_prolog_flag(argv, Args),
        Args = [_ | Args2],
        parse_args2(Args2, Sources).
parse_args(_) :-
        write_error('invalid command-line arguments'),
        help,
        !,
        fail.

%! parse_args2(+Args:list, -Sources:list)
% Checks individual arguments given from command-line. Call parse_args/1
% instead of this.
%
% @param Args List of command-line arguments.
% @param Sources Paths of input files.
parse_args2([X | T], S) :-
        member(X, ['-v', '--verbose']),
        !,
        set_user_option(verbose, 1),
        parse_args2(T, S).
parse_args2([X | T], S) :-
        member(X, ['-vv', '--veryverbose']),
        !,
        set_user_option(veryverbose, 1),
        parse_args2(T, S).
parse_args2([X | T], S) :-
        member(X, ['-a', '--auto']),
        !,
        set_user_option(mode, auto),
        parse_args2(T, S).
parse_args2([X | T], S) :-
        member(X, ['-i', '--interactive']),
        !,
        set_user_option(mode, user),
        parse_args2(T, S).
parse_args2([X | T], S) :-
        atom_chars(X, ['-', 's' | Nc]),
        Nc \= [],
        number_chars(N, Nc),
        N >= 0,
        !,
        set_user_option(ascount, N),
        set_user_option(ascount), % allow user-specified value to override hard-coded ones
        parse_args2(T, S).
parse_args2([X | T], S) :-
        X = '-s',
        !,
        set_user_option(ascount, 0), % find all
        set_user_option(ascount), % allow user-specified value to override hard-coded ones
        parse_args2(T, S).
parse_args2([X | T], S) :- % intentionally undocumented option to enable debugging
        atom_chars(X, ['-', 'd' | Nc]),
        Nc \= [],
        number_chars(N, Nc),
        N >= 0,
        !,
        set_user_option(debug, N),
        parse_args2(T, S).
parse_args2([X | T], S) :-
        X = '-d',
        !,
        set_user_option(debug, 0), % lowest level that actually adds debugging output
        parse_args2(T, S).
parse_args2([X | T], S) :-
        X = '-j',
        !,
        set_user_option(justification, true),
        parse_args2(T, S).
parse_args2([X | T], S) :-
        X = '-n',
        !,
        set_user_option(hide_nmr, true),
        parse_args2(T, S).
parse_args2([X | T], S) :-
        X = '-la',
        !,
        set_user_option(list_abducibles, true),
        parse_args2(T, S).
parse_args2([X | T], S) :-
        member(X, ['-?', '-h', '--help']),
        !,
        set_user_option(help, 1),
        parse_args2(T, S).
parse_args2([X | T], [X | S]) :-
        \+ atom_concat('-', _, X), % if it isn't a flag, assume source file.
        !,
        parse_args2(T, S).
parse_args2([], []).
