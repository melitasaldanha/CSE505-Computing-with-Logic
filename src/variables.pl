:- module(variables, [
                        var_con/4,
                        is_var/1,
                        is_unbound/5,
                        is_ground/2,
                        new_var_struct/1,
                        var_value/3,
                        update_var_value/4,
                        add_var_constraint/4,
                        get_value_id/3,
                        variable_intersection/4,
                        unify_vars/5,
                        test_constraints/4,
                        body_vars/3,
                        body_vars2/4,
                        get_unique_vars/6,
                        generate_unique_var/3,
                        print_var_struct/1,
                        replace_vars_in_all/5,
                        replace_vars/7
                     ]).

/** <module> Variable storage and access

Predicates related to storing, accessing and modifying variables.

@author Kyle Marple
@version 20170831
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
:- use_module(library(rbtrees)).
:- use_module(library(writef)).
:- use_module(common).
:- use_module(debug).
:- use_module(output). % for format_term/4.
:- use_module(solve). % for unification.

%! var_struct(?VarStruct:compound, ?Variables:list, ?Values:list, ?NameCnt:int, ?IDCnt:int) is det
% Convert a var struct to its components or vice-versa. The purpose of the var
% struct is to allow emulation of Prolog unification in cases such as
%   X = Y, X = a.
% That is, unified variables should point to a common memory location rather
% than each-other. This is emulating by giving them the same value ID and
% storing the actual values in a separate list with the corresponding IDs.
% This shouldn't be accessed outside of this module. 
%
% @param VarStruct A variable struct pairing a variable list and a value list.
% @param Variables A list of pairs linking variables with a value ID.
% @param Values A list of pairs linking value IDs to values or constraint lists.
% @param NameCnt The counter used to create unique variable names.
% @param IDCnt The counter used to create unique variable value IDs.
var_struct(-(Var, Val, Cnt, Cnt2), Var, Val, Cnt, Cnt2).

%! var_con(?Struct:compound, ?Constraints:list, ?Unbindable:int, ?LoopVar:int) is det
% Convert a var_con struct to its components and vice-versa.
%
% @param Struct The structure.
% @param Constraints The list of constraint values.
% @param Unbindable 0, 1 or 2 indicating if binding (1) or further constraining
%        via disunification (2) the variable should trigger failure.
% @param LoopVar -1, 0 or 1 indicating if the variable succeeded non-ground in a
%        positive loop. If -1, the variable is part of a forall and CANNOT be
%        made a loop variable (any attempt to do so must fail).
var_con(con(C, U, L), C, U, L).

%! is_var(+Test:compound) is det
% Test an entry to see if it's a variable (the first non-underscore is an
% upper-case letter.
%
% @param Test The item to be tested.
is_var(X) :-
        atom(X),
        atom_chars(X, Xc),
        is_var2(Xc),
        !.
        
%! is_var2(+TestChars:list) is det
% Check characters in a list to see if the first non-underscore is an upper-case
% letter, indicating a variable.
%
% @param TestChars The characters for an atom or variable.
is_var2([X | _]):-
        char_type(X, upper),
        !.
is_var2(['_']).
is_var2([X | T]) :-
        member(X, ['_', '?']),
        !,
        is_var2(T).

%! is_unbound(+Goal:compound, +Vars:compound, -Constraints:list, -Flag:int, -LoopVar:int) is det
% Given a goal, succeed if it is an unbound (possibly constrained) variable.
%
% @param Goal The input goal.
% @param Vars The list of variable values and constraints.
% @param Constraints The list of constraints. Empty if completely unbound.
% @param Flag 0, 1 or 2 indicating if binding (1) or further constraining via
%        disunification (2) should trigger failure.
% @param LoopVar -1, 0 or 1 indicating if the variable succeeded non-ground in a
%        positive loop. If -1, the variable is part of a forall and CANNOT be
%        made a loop variable (any attempt to do so must be ignored).
is_unbound(G, V, C, F, L) :-
        is_var(G),
        var_value(G, V, Val),
        var_con(Val, C, F, L), % unbound or constrained
        !.

%! is_ground(+Goal:compound, +Vars:compound) is det
% Succeed if goal contains no unbound or constrained variables. Recursively
% check args of compound terms.
%
% @param Goal The goal to be tested.
% @param Vars The variable struct to get values from.
is_ground(X, V) :-
        is_unbound(X, V, _, _, _),
        !,
        fail.
is_ground(X, V) :-
        is_var(X),
        !,
        once(var_value(X, V, val(Val))), % bound variable; check value. check value
        is_ground(Val, V).
is_ground(X, V) :-
        X =.. [_ | A],
        A \= [], % compound term
        !,
        is_ground2(A, V).
is_ground(_, _) :-
        !. % not a variable or compound term; succeed.

%! is_ground2(+Goals:list, +Vars:compound) is det
% Succeed if is_ground/2 succeeds for each member of Goals.
%
% @param Goals The goals to be tested.
% @param Vars The variable struct to get values from.
is_ground2([X | T], V) :-
        is_ground(X, V),
        !,
        is_ground2(T, V).
is_ground2([], _) :-
        !.

%! new_var_struct(-VarStruct:compound) is det
% Create an empty var struct. The search spaces are empty Red-Black trees and
% the counters are initialized to 0.
%
% @param VarStruct A variable structure.
new_var_struct(-(X, Y, 0, 0)) :-
        rb_empty(X),
        rb_empty(Y),
        !.

%! var_value(+Variable:ground, +VarStruct:compound, -Value:compound) is det
% Given a variable and a variable struct, get the value for the given
% variable, if present. Otherwise, return an empty list, indicating that the
% variable is unbound. Value will be either a binding or a list of values the 
% variable cannot take (constraints). Any forall variables (loopvar flag = -1)
% are expected to be in the variable struct. Thus any non-loop variables not
% present may be given a loop var flag of 0.
%
% @param Variable The variable.
% @param VarStruct The variable struct.
% @param Value The value of the variable. 
var_value(V, Vs, Val) :- % variable present in list
        is_var(V),
        var_struct(Vs, V1, V2, _, _),
        rb_lookup(V, ID, V1), % get ID
        !,
        get_val_by_id(ID, V2, Val).
var_value(V, _, Val) :- % variable not in list; completely unbound
        is_var(V), % fail if not a variable at all
        atom_chars(V, [C | _]),
        C \= '?', % not flagged
        var_con(Val, [], 0, 0).
var_value(V, _, Val) :- % variable not in list; completely unbound
        is_var(V), % fail if not a variable at all
        atom_chars(V, ['?' | _]), % flagged (printing only)
        var_con(Val, [], 0, 1).

%! get_val_by_id(+ID:int, +ValStruct:compound, -Value:compound) is det
% Given a variable value ID, get the corresponding value. If it links to another
% ID, check that one recursively.
%
% @param ID The ID.
% @param ValStruct The value struct from a variable struct.
% @param Value The value associated with the ID. 
get_val_by_id(I, Vs, Vo) :-
        rb_lookup(I, Val, Vs), % bind Val
        (
                Val = id(I2), % check recursively
                get_val_by_id(I2, Vs, Vo)
        ;
                Vo = Val % value found
        ),
        !.

%! update_var_value(+Var:ground, +Value:compound, +VarStructIn:compound, -VarStructOut:compound) is det
% Update the value of a variable. Value must be of the form val(Val),
% con(Cons, Flag, Flag2) or id(ID).
%
% @param Var The variable.
% @param Value The new value.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
update_var_value(V, Val, Vsi, Vso) :-
        is_var(V),
        var_struct(Vsi, V1, V2, NextVar, NextID),
        get_value_id(V, ID, Vsi), % present in var struct; binds the ID to update
        !,
        rb_update(V2, ID, Val, V3), % update value
        var_struct(Vso, V1, V3, NextVar, NextID), % repack the struct
        !.
update_var_value(V, Val, Vsi, Vso) :-
        is_var(V), % not present in var struct; add it
        var_struct(Vsi, V1, V2, NV, ID),
        rb_insert(V1, V, ID, V3), % create variable entry
        rb_insert(V2, ID, Val, V4), % create value entry
        ID2 is ID + 1, % update NextID
        var_struct(Vso, V3, V4, NV, ID2), % pack the struct
        !.

%! add_var_constraint(+Var:ground, +Constraint:compound, +VarStructIn:compound, -VarStructOut:compound) is det
% Add a new constraint to an unbound or previously constrained variable.
% For cases involving loop variables with other variables, only the loop
% variables are constrained. Forall variables can only be called with loop
% variables.
%
% @param Var The variable. Unbound or constrained.
% @param Constraint The new constraint.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
add_var_constraint(V, C, Vsi, Vso) :-
        \+is_var(C),
        is_unbound(V, Vsi, Cs, F, L),
        F =< 1, % we are allowed to add constraints
        !,
        add_var_constraint2(val(C), Cs, Cs2),
        var_con(Val2, Cs2, F, L),
        update_var_value(V, Val2, Vsi, Vso).
add_var_constraint(V, C, Vsi, Vso) :-
        is_var(C),
        var_value(C, Vsi, val(Cv)),
        is_unbound(V, Vsi, Cs, F, L), % get existing constraints
        F =< 1, % we are allowed to add constraints
        !,
        add_var_constraint2(val(Cv), Cs, Cs2),
        var_con(Val2, Cs2, F, L),
        update_var_value(V, Val2, Vsi, Vso).
add_var_constraint(V, C, Vsi, Vso) :-
        is_var(C),
        is_unbound(V, Vsi, Cs, F, 1), % V is an unbound or constrained LOOP var
        is_unbound(C, Vsi, _, _, _), % C is an unbound or constrained var
        F =< 1, % we are allowed to add constraints
        !,
        get_value_id(V, I1, Vsi), % get IDs
        get_value_id(C, I2, Vsi),
        I1 =\= I2, % can't constrain a var against itself or one unified with it
        if_debug(5, writef('add_var_constraint: adding loop variable constraint for %w against %w\n', [V, C])),
        add_var_constraint2(var(C), Cs, Cs2), % add constraint to loop var ONLY
        var_con(V2, Cs2, F, 1),
        update_var_value(V, V2, Vsi, Vso).
add_var_constraint(V, C, Vsi, Vso) :-
        is_var(C),
        is_unbound(V, Vsi, _, _, _), % V is an unbound or constrained var
        is_unbound(C, Vsi, Cs, F, 1), % C is an unbound or constrained LOOP var
        F =< 1, % we are allowed to add constraints
        !,
        get_value_id(V, I1, Vsi), % get IDs
        get_value_id(C, I2, Vsi),
        I1 =\= I2, % can't constrain a var against itself or one unified with it
        if_debug(5, writef('add_var_constraint: adding loop variable constraint for %w against %w\n', [C, V])),
        add_var_constraint2(var(V), Cs, Cs2), % add constraint to loop var ONLY
        var_con(C2, Cs2, F, 1),
        update_var_value(C, C2, Vsi, Vso).
add_var_constraint(V, C, Vsi, Vso) :-
        is_var(C),
        is_unbound(V, Vsi, Cs1, F1, 0), % V is an unbound or constrained non-forall, non-loop var
        is_unbound(C, Vsi, Cs2, F2, 0), % C is an unbound or constrained non-forall, non-loop var
        F1 =< 1, % we are allowed to add constraints
        F2 =< 1,
        !,
        get_value_id(V, I1, Vsi), % get IDs
        get_value_id(C, I2, Vsi),
        I1 =\= I2, % can't constrain a var against itself or one unified with it
        if_debug(5, writef('add_var_constraint: adding mutual constraints for vars %w and %w\n', [V, C])),
        add_var_constraint2(var(C), Cs1, Cs12), % add mutual var constraints
        add_var_constraint2(var(V), Cs2, Cs22),
        var_con(V2, Cs12, F1, 0),
        var_con(C2, Cs22, F2, 0),
        update_var_value(V, V2, Vsi, Vs1),
        update_var_value(C, C2, Vs1, Vso).

%! add_var_constraint2(+Val:compound, +ConsIn:list, -ConsOut:list) is det
% Insert a constraint while keeping the list sorted.
%
% @param Val The value to insert.
% @param ConsIn Input constraints.
% @param ConsOut Output constraints.
add_var_constraint2(V, [], [V]) :-
        !.
add_var_constraint2(V, [X | T], [X | T2]) :-
        X @< V,
        !,
        add_var_constraint2(V, T, T2).
add_var_constraint2(V, [X | T], [V, X | T]) :-
        X @> V,
        !.
add_var_constraint2(X, [X | T], [X | T]) :- % Already present
        !.

%! var_id(+Variable:ground, +VarStruct:compound, -Value:compound) is det
% Given a variable and a variable struct, get the ID for the given
% variable. Fail if not present.
%
% @param Variable The input variable.
% @param VarStruct The variable struct.
% @param ID The ID of the variable. 
var_id(V, Vs, ID) :-
        is_var(V),
        var_struct(Vs, V1, _, _, _),
        rb_lookup(V, ID, V1), % binds ID
        !.

%! get_value_id(+Var:ground, -ID:int, +VarStruct:compound) is det
% Given a variable, get the final ID linked to it in the VarStruct. That is, if
% its value links to another ID, recursively process it until an actual value is
% found.
%
% @param Var The variable.
% @param ID The value ID.
% @param VarStruct Var struct.
get_value_id(V, ID, Vs) :-
        is_var(V),
        var_struct(Vs, V1, V2, _, _),
        rb_lookup(V, I, V1), % binds ID
        rb_lookup(I, Val, V2), % binds Val
        !,
        (Val = id(ID2) -> % id found, check it
                get_value_id2(ID2, ID, Vs)
        ;
                ID = I % value found; we're done
        ),
        !.

%! get_value_id2(+IDin:int, -IDout:int, +VarStruct:compound) is det
% Given an ID, get the final ID linked to it in the VarStruct. That is, if
% its value links to another ID, recursively process it until an actual value is
% found.
%
% @param IDin The initial ID.
% @param IDout The final ID.
% @param VarStruct Var struct.
get_value_id2(Ii, Io, Vs) :-
        var_struct(Vs, _, V2, _, _),
        rb_lookup(Ii, Val, V2),
        !,
        (Val = id(I2) ->  % id found, check it
                get_value_id2(I2, Io, Vs)
        ;
                Io = Ii % value found; use current ID
        ).

%! get_value_ids(+Variables:list, -IDs:list, +VarStruct:compound) is det
% For each variable in a list, get the value ID.
%
% @param Variable The input list.
% @param IDs The list of IDs.
% @param VarStruct The variable struct.
get_value_ids([X | T], [I | T2], Vs) :-
        get_value_id(X, I, Vs),
        !,
        get_value_ids(T, T2, Vs).
get_value_ids([], [], _) :-
        !.

%! variable_intersection(+Goal1:compound, +Goal2:compound, +VarStruct:compound, -IntersectionVars:list)
% Given two goals, get the non-ground variables present in each, then return
% those variables present in both lists.
%
% @param Goal1 The first goal.
% @param Goal2 The second goal.
% @param VarStruct The variable struct.
% @param IntersectionVars The list of intersecting non-bound variables.
variable_intersection(G1, G2, Vs, Gv) :-
        body_vars2([G1], [], [], V1),
        remove_bound(V1, Vs, V12),
        body_vars2([G2], [], [], V2),
        remove_bound(V2, Vs, V22),
        get_value_ids(V12, I1, Vs),
        get_value_ids(V22, I2, Vs),
        list_intersection(I1, I2, Is),
        ids_to_vars(Is, V12, Vs, Gv1),
        sort(Gv1, Gv). % order and remove duplicates

%! remove_bound(+VarsIn:list, +VarStruct:compound, -VarsOut:list)
% Given a list of variables, remove those which are bound to a single value.
%
% @param VarsIn Input variables.
% @param VarStruct The variable struct.
% @param VarsOut Output variables.
remove_bound([X | T], Vs, [X | T2]) :-
        is_unbound(X, Vs, _, _, _),
        !,
        remove_bound(T, Vs, T2).
remove_bound([_ | T], Vs, T2) :-
        !,
        remove_bound(T, Vs, T2).
remove_bound([], _, []) :-
        !.

%! ids_to_vars(+IDs:list, +GoalVars:list, +VarStruct:compound, -IDVars:list)
% Convert a list of IDs to variables from GoalVars. Note that every member of
% IDs must have a match in GoalVars, but the reverse need not hold.
%
% @param IDs List of variable IDs.
% @param GoalVars List of variables which includes matches for IDs.
% @param VarStruct The variable struct.
% @param IDVars List of variables corresponding to the IDs.
ids_to_vars([X | T], Gv, Vs, [X2 | T2]) :-
        id_to_var(X, Gv, Vs, X2),
        !,
        ids_to_vars(T, Gv, Vs, T2).
ids_to_vars([], _, _, []) :-
        !.

%! id_to_var(+ID:int, +GoalVarsIn:list, +VarStruct:compound, -IDVar:list)
% Convert a list of IDs to variables from GoalVars. Note that every member of
% IDs must have a match in GoalVars, but the reverse need not hold.
%
% @param IDs List of variable IDs.
% @param GoalVarsIn Input list of variables which includes a match for ID.
% @param VarStruct The variable struct.
% @param IDVars Variable corresponding to the ID.
id_to_var(X, [Y | _], Vs, Y) :-
        get_value_id(Y, I, Vs),
        X =:= I, % match
        !.
id_to_var(X, [_ | T], Vs, Iv) :-
        !, % keep looking
        id_to_var(X, T, Vs, Iv).

%! unify_vars(+Var1:ground, +Var2:ground, +VarStructIn:compound, -VarStructOut:compound, +OccursCheck:int) is det
% Unify two variables by updating the value of the first to the Most General
% Unifier and linking the second to the first.
%
% @param Var1 Variable one.
% @param Var2 Variable two.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
% @param OccursCheck 1 or 0 indicating whether or not to perform the occurs
%        check when unifying a variable with a structure.
unify_vars(V1, V2, Vs, Vs, _) :-
        get_value_id(V1, I, Vs),
        get_value_id(V2, I, Vs), % Variables are already unified.
        %writef('uv a: unifying %w, ID %w with %w, ID %w\n', [V1, I, V2, I2]),
        !.
unify_vars(V1, V2, Vsi, Vso, _) :-
        is_unbound(V1, Vsi, C1, F1, L1),
        is_unbound(V2, Vsi, C2, F2, L2), % both are unbound or constrained
        !,
        if_debug(5, writef('unify_vars a: %w and %w\n', [V1, V2])),
        (get_value_id(V1, I1, Vsi) -> % V1 has an entry in variable store
                findall(I22, (member(var(X2), C2), get_value_id(X2, I22, Vsi)), Is2), % get IDs for any var constraints on V2
                \+member(I1, Is2) % vars aren't constrained against eachother.
        ;
                true
        ),
        (get_value_id(V2, I2, Vsi) -> % V2 has an entry in variable store
                findall(I12, (member(var(X1), C1), get_value_id(X1, I12, Vsi)), Is1), % get IDs for any var constraints on V1
                \+member(I2, Is1) % vars aren't constrained against eachother.
        ;
                true
        ),
        if_debug(5, writef('unify_vars a1: merging %w and %w\n', [C1, C2])),
        !,
        %writef('uv b, vars = %w\n', [Vsi]),
        merge_constraints(C1, C2, C3), % get the MGU (here, merged constraints)
        ((F1 =:= 1 ; F2 =:= 1) ->
                F3 is 1
        ;
                F3 is 0
        ),
        ((L1 =:= -1 ; L2 =:= -1) -> % if either var is unloopable or a loop var, both must be
                L3 is -1
        ;
                L3 is max(L1, L2)
        ),
        var_con(Val, C3, F3, L3),
        update_var_value(V1, Val, Vsi, Vs1), % update the value to the MGU
        var_id(V1, Vs1, ID),
        update_var_value(V2, id(ID), Vs1, Vso), % Link V2 to V1
        !.
unify_vars(V1, V2, Vsi, Vso, O) :-
        is_unbound(V1, Vsi, Con, F, _), % variable two is bound
        !,
        var_value(V2, Vsi, val(Val)),
        if_debug(5, writef('unify_vars b: %w \\= %w and %w = %w\n', [V1, Con, V2, Val])),
        F \= 1, % variable is bindable; else fail
        (var_id(V2, Vsi, ID) ->
                \+member(var(ID), Con) % V1 isn't constrained against V2
        ;
                true
        ),
        !,
        if_debug(5, writef('unify_vars b1: testing constraints\n', [])),
        once(test_constraints(Con, val(Val), Vsi, Vs1)), % ensure no constraints are violated.
        (O =:= 1 ->
                occurs_check(V1, Val, Vsi)
        ;
                true
        ),
        update_var_value(V1, id(ID), Vs1, Vso), % Link V1 to V2
        !.
unify_vars(V1, V2, Vsi, Vso, O) :-
        is_unbound(V2, Vsi, Con, F, _), % variable one is bound
        !,
        if_debug(5, writef('unify_vars c: %w and %w\n', [V1, V2])),
        F \= 1,
        (var_id(V1, Vsi, ID) ->
                \+member(var(ID), Con) % V2 isn't constrained against V1
        ;
                true
        ),
        !,
        var_value(V1, Vsi, val(Val)),
        once(test_constraints(Con, val(Val), Vsi, Vs1)), % ensure no constraints are violated.
        (O =:= 1 ->
                occurs_check(V2, Val, Vsi)
        ;
                true
        ),
        update_var_value(V2, id(ID), Vs1, Vso), % Link V1 to V2
        !.
unify_vars(V1, V2, Vsi, Vso, O) :- % both are at least partially bound
        var_value(V1, Vsi, val(Val)),
        var_value(V2, Vsi, val(Val2)),
        !,
        if_debug(5, writef('unify_vars d: %w and %w\n', [V1, V2])),
        (O =:= 1 ->
                occurs_check(V1, Val2, Vsi),
                occurs_check(V2, Val, Vsi)
        ;
                true
        ),
        solve_unify(Val, Val2, Vsi, Vs1, O), % unify the two values.
        var_id(V1, Vs1, ID),
        update_var_value(V2, id(ID), Vs1, Vso), % Link V2 to V1
        !.

%! test_constraints(+Constraints:list, +Value:compound, +VarStructIn:compound, +VarStructOut:compound)
% Given a list of constraints and a non-variable value, ensure that none of the
% constraints unify with the value. For unbound, non-forall variable
% constraints, just succeed; there will always be some value the variable can
% take that will not unify with the value.
%
% @param Constraints A list of values that a variable cannot take.
% @param Value A value to check. May be ground or partially ground.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
test_constraints([val(X) | T], V, Vsi, Vso) :-
        X =.. [F | A1],
        V =.. [F | A2], % Compound terms with same functor
        length(A1, L1),
        length(A2, L2),
        L1 =:= L2, % same arity
        !,
        once(solve_subdnunify(A1, A2, Vsi, Vs1, Flag)),
        (
                (Flag = 1, Vs2 = Vs1) % doesn't unify, but keep any changes
        ;
                (Flag = 2, Vs2 = Vsi) % doesn't unify, but drop any variable changes
        ),
        !,
        test_constraints(T, V, Vs2, Vso).
test_constraints([val(X) | T], V, Vsi, Vso) :-
        X =.. [_ | _],
        V =.. [_ | _], % Compound terms with differing functors or arity
        !,
        test_constraints(T, V, Vsi, Vso).
test_constraints([val(X) | T], V, Vsi, Vso) :-
        X \= V, % at least one is not a compound term
        !,
        test_constraints(T, V, Vsi, Vso).
test_constraints([var(X) | T], V, Vsi, Vso) :-
        var_value(X, Vsi, val(Val)), % variable has been bound
        !,
        test_constraints([val(Val)], V, Vsi, Vs1), % test variable value
        test_constraints(T, V, Vs1, Vso).
test_constraints([var(X) | T], V, Vsi, Vso) :-
        is_unbound(X, Vsi, _, _, L),
        L >= 0, % not a forall variable
        !,
        test_constraints(T, V, Vsi, Vso).
test_constraints([var(X) | _], _, Vsi, _) :-
        is_unbound(X, Vsi, _, _, -1),
        !,
        writef('test_constraints: testing against forall variable %w. THIS SHOULD NOT HAPPEN!\n', [X]),
        fail.
test_constraints([], _, Vs, Vs) :-
        !.

%!merge_constraints(+ListA:list, +ListB:list, -ListC:list) is det
% Merge variable constraint lists A and B into list C.
%
% @param ListA Input list 1.
% @param ListB Input list 2.
% @param ListC Output list.
merge_constraints([], X, X) :-
        !.
merge_constraints(X, [], X) :-
        !.
merge_constraints([X | T], Y, Z) :-
        member(X, Y), % skip duplicates
        !,
        merge_constraints(T, Y, Z).
merge_constraints([X | T], Y, [X | T2]) :-
        !, % not a duplicate
        merge_constraints(T, Y, T2).

%! body_vars(+Head:compound, +Body:list, -BodyVars:list) is det
% Get the body variables (variables used in the body but not in the head) for a
% clause.
body_vars(H, B, Bv) :-
        body_vars3(H, [], [], Hv), % get variables in head
        body_vars2(B, Hv, [], Bv).

%! body_vars2(+Body:list, +HeadVars:list, +BodyVarsIn:list, -BodyVarsOut:list) is det
% For each goal in a list, get the variables that are not present in the list of
% head variables. Note that this can be used to get all variables in a list of
% goals by calling it with an empty list of head variables.
%
% @param Body The list of goals in the clause.
% @param HeadVars The list of variables in the head.
% @param BodyVarsIn Input body vars.
% @param BodyVarsOut Output body vars.
body_vars2([X | T], Hv, Bvi, Bvo) :-
        body_vars3(X, Hv, Bvi, Bv1),
        !,
        body_vars2(T, Hv, Bv1, Bvo).
body_vars2([], _, Bv, Bv) :-
        !.

%! body_vars3(+Goal:compound, +HeadVars:list, +BodyVarsIn:list, -BodyVarsOut:list) is det
% For a single goal, get the variables that are not present in the list of head
% variables. This predicate can get all of the variables in a goal if HeadVars
% is empty. The list of variables will be in the order they are encountered.
%
% @param Goal The list of goals in the clause.
% @param HeadVars The list of variables in the head.
% @param BodyVarsIn Input body vars.
% @param BodyVarsOut Output body vars.
body_vars3(G, Hv, Bvi, Bvo) :-
        is_var(G), % variable
        \+member(G, Hv), % not a head variable
        \+member(G, Bvi), % not already encountered
        append(Bvi, [G], Bvo), % keep proper order.
        !.
body_vars3(G, Hv, Bvi, Bvo) :-
        G =.. [_ | A],
        A \= [], % goal is a compound term
        body_vars2(A, Hv, Bvi, Bvo), % check args for variables
        !.
body_vars3(_, _, Bv, Bv) :- % not a compound term or a new, non-head variable
        !.

%! get_unique_vars(+HeadIn:compound, -HeadOut:compound, +BodyIn:list, -BodyOut:list, +VarsIn:compound, -VarsOut:compound)
% Given the head and body of a clause being expanded, replace every variable
% with a unique one using the counter in the var struct.
%
% @param HeadIn Input head.
% @param HeadOut Output head.
% @param BodyIn Input body.
% @param BodyOut Output body.
% @param VarsIn Input var struct.
% @param VarsOut Output var struct.
get_unique_vars(Hi, Ho, Bi, Bo, Vi, Vo) :-
        get_unique_vars3(Hi, Ho, Vi, V1, [], Vt),
        get_unique_vars2(Bi, Bo, V1, Vo, Vt, _). % update counter

%! get_unique_vars2(+GoalsIn:list, -GoalsOut:list, +VarStructIn:int, -VarStructOut:int, +VarsIn:compound, -VarsOut:compound)
% Given a list of goals, replace every variable with a unique one using the
% counter in the var struct. If the variable has already been replaced, use the
% same replacement value.
%
% @param GoalsIn Input goals.
% @param GoalsOut Output goals.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
% @param VarsIn Input vars.
% @param VarsOut Output vars.
get_unique_vars2([Xi | Ti], [Xo | To], Ci, Co, Vi, Vo) :-
        get_unique_vars3(Xi, Xo, Ci, C1, Vi, V1),
        !,
        get_unique_vars2(Ti, To, C1, Co, V1, Vo).
get_unique_vars2([], [], C, C, V, V).

%! get_unique_vars3(+Goal:compound, -GoalOut:compound, +VarStructIn:int, -VarStructOut:int, +VarsIn:compound, -VarsOut:compound)
% Given a goal, replace each variable with a unique one. If a variable has
% already been replaced, use the same assignment.
% @param GoalIn Input goal.
% @param GoalOut Output goal.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
% @param VarsIn Input vars.
% @param VarsOut Output vars.
get_unique_vars3(Gi, Go, Vs, Vs, V, V) :-
        is_var(Gi),
        member(-(Gi, Go), V), % already encountered, use the same value
        !.
get_unique_vars3(Gi, Go, Vsi, Vso, Vi, Vo) :-
        is_var(Gi), % not encountered, generate a value.
        !,
        generate_unique_var(Go, Vsi, Vso),
        Vo = [-(Gi, Go) | Vi],
        !.
get_unique_vars3(Gi, Go, Vsi, Vso, Vi, Vo) :-
        Gi =.. [F | A], % compound term, process args
        !,
        get_unique_vars2(A, A2, Vsi, Vso, Vi, Vo),
        Go =.. [F | A2],
        !.
get_unique_vars3(G, G, Vs, Vs, V, V) :-
        % not a variable or compound term; skip it.
        !.

%! generate_unique_var(-Var:ground, +VarsIn:compound, -VarsOut:compound) is det
% Using the counter in the variable struct, generate a unique variable name and
% then update the counter by incrementing it.
%
% @param Var The newly generated variable.
% @param VarsIn Input vars.
% @param VarsOut Output vars.
generate_unique_var(Var, Vi, Vo) :-
        var_struct(Vi, V1, V2, Ci, I), % get initial counter value.
        number_chars(Ci, Cc),
        atom_chars(Var, ['V', 'a', 'r' | Cc]),
        Co is Ci + 1,
        var_struct(Vo, V1, V2, Co, I), % repack the struct
        !.

%! print_var_struct(+Vars:compound) is det
% Print the two main components of the variable struct for debugging purposes:
% the variable/id list and the id/value list.
%
% @param Vars Variable struct to print
print_var_struct(V) :-
        var_struct(V, Vid, Vval, _, _),
        rb_visit(Vid, Vid2),
        rb_visit(Vval, Vval2),
        writef('\n\nRAW VARIABLE ID TABLE:\n%w\n\n', [Vid2]),
        writef('RAW ID VALUE TABLE:\n%w', [Vval2]).

%! replace_vars_in_all(+GoalsIn:list, -GoalsOut:list, +VarStructIn:int, -VarStructOut:int, +Flag:int) is det
% Given a list of lists of goals, replace NON-LOOP variables in each with unique
% ones. Ignore unbound or constrained loop variables.
%
% @param GoalsIn Input goals.
% @param GoalsOut Output goals.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
% @param Flag 0 or 1 indicating if non-loop variables should be set as
%        non-unifiable.
replace_vars_in_all([X | T], [X2 | T2], Vsi, Vso, F) :-
        replace_vars(X, X2, Vsi, Vs1, [], _, F),
        !,
        replace_vars_in_all(T, T2, Vs1, Vso, F).
replace_vars_in_all([], [], Vs, Vs, _) :-
        !.

%! replace_vars(+GoalsIn:list, -GoalsOut:list, +VarStructIn:int, -VarStructOut:int, +VarsIn:compound, -VarsOut:compound, +Flag:int) is det
% Given a list of goals, replace every bound variable with its value and every
% constrained or unbound NON-LOOP variable with a unique one that has the same
% constraints. If the variable has already been replaced, use the same
% replacement value. Ignore unbound or constrained loop variables.
%
% @param GoalsIn Input goals.
% @param GoalsOut Output goals.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
% @param VarsIn Input vars.
% @param VarsOut Output vars.
% @param Flag 0 or 1 indicating if non-loop variables should be set as
%        non-unifiable.
replace_vars([Xi | Ti], [Xo | To], Vsi, Vso, Vi, Vo, F) :-
        replace_vars2(Xi, Xo, Vsi, Vs1, Vi, V1, F),
        !,
        replace_vars(Ti, To, Vs1, Vso, V1, Vo, F).
replace_vars([], [], Vs, Vs, V, V, _).

%! replace_vars2(+Goal:compound, -GoalOut:compound, +VarStructIn:int, -VarStructOut:int, +VarsIn:compound, -VarsOut:compound, +Flag:int)
% Given a goal, replace every bound variable with its value and
% every constrained or unbound NON-LOOP variable with a unique one that has the
% same constraints. If the variable has already been replaced, use the same
% replacement value. Ignore unbound or constrained loop variables.
%
% @param GoalIn Input goal.
% @param GoalOut Output goal.
% @param VarStructIn Input var struct.
% @param VarStructOut Output var struct.
% @param VarsIn Input vars.
% @param VarsOut Output vars.
% @param Flag 0 or 1 indicating if non-loop variables should be set as
%        non-unifiable.
replace_vars2(Gi, Go, Vs, Vs, V, V, _) :-
        is_var(Gi),
        member(-(Gi, Go), V), % already encountered, use the same value
        !.
replace_vars2(Gi, Gi, Vsi, Vsi, Vi, Vo, _) :-
        is_unbound(Gi, Vsi, _, _, 1), % unbound or constrained variable, loop variable
        !,
        Vo = [-(Gi, Gi) | Vi].
replace_vars2(Gi, Go, Vsi, Vso, Vi, Vo, 0) :-
        is_unbound(Gi, Vsi, Con, _, Vl), % unbound or constrained variable, non-loop variable
        Vl =\= 1,
        !,
        var_con(Val, Con, 0, Vl), % ALLOW further constraints or instantiation.
        generate_unique_var(Go, Vsi, Vs1),
        update_var_value(Go, Val, Vs1, Vso), % copy value to new variable
        Vo = [-(Gi, Go) | Vi].
replace_vars2(Gi, Go, Vsi, Vso, Vi, Vo, 1) :-
        is_unbound(Gi, Vsi, Con, _, Vl), % unbound or constrained variable, non-loop variable
        Vl =\= 1,
        !,
        var_con(Val, Con, 2, Vl), % DISALLOW further constraints or instantiation.
        generate_unique_var(Go, Vsi, Vs1),
        update_var_value(Go, Val, Vs1, Vso), % copy value to new variable
        Vo = [-(Gi, Go) | Vi].
replace_vars2(Gi, Val2, Vsi, Vso, Vi, Vo, Flag) :-
        is_var(Gi),
        var_value(Gi, Vsi, val(Val)),
        Val =.. [F | A], % compound term
        !,
        replace_vars(A, A2, Vsi, Vso, Vi, V1, Flag),
        Val2 =.. [F | A2],
        Vo = [-(Gi, Val2) | V1].
replace_vars2(Gi, Val, Vs, Vs, Vi, Vo, _) :-
        is_var(Gi),
        !,
        var_value(Gi, Vs, val(Val)), % not unbound, constrained or a compound term
        Vo = [-(Gi, Val) | Vi].
replace_vars2(Gi, Go, Vsi, Vso, Vi, Vo, Flag) :-
        Gi =.. [F | A], % compound term, process args
        !,
        replace_vars(A, A2, Vsi, Vso, Vi, Vo, Flag),
        Go =.. [F | A2].
replace_vars2(G, G, Vs, Vs, V, V, _) :-
        % not a variable or compound term; keep original.
        !.
