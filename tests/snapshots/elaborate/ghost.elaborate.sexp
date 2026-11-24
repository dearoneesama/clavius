(SortDecl $Fuel)
(FunDecl $zero [] $Fuel)
(FunDecl $succ [(VarDecl $fuel $Fuel)] $Fuel)
(FunDecl tri$1 [(VarDecl $fuel $Fuel) (VarDecl n$2 int)] int)
(FunDecl $ok$tri$1 [] bool)
(FunDecl double$4 [(VarDecl $fuel $Fuel) (VarDecl n$5 int)] int)
(FunDecl $ok$double$4 [] bool)
(Axiom
  (BinOp =>
    (App $ok$tri$1 [])
    (Forall
      [(VarDecl $fuel $Fuel) (VarDecl n$2 int)]
      [(Trigger [(App tri$1 [(App $succ [(Var $fuel)]) (Var n$2)])])]
      (BinOp ==
        (App tri$1 [(App $succ [(Var $fuel)]) (Var n$2)])
        (App tri$1 [(Var $fuel) (Var n$2)])))))
(Axiom
  (BinOp =>
    (App $ok$tri$1 [])
    (Forall
      [(VarDecl $fuel $Fuel) (VarDecl n$2 int)]
      [(Trigger [(App tri$1 [(App $succ [(Var $fuel)]) (Var n$2)])])]
      (BinOp =>
        (BinOp <= (Int 0) (Var n$2))
        (BinOp ==
          (App tri$1 [(App $succ [(Var $fuel)]) (Var n$2)])
          (Ite
            (BinOp == (Var n$2) (Int 0))
            (Int 0)
            (BinOp + (App tri$1 [(Var $fuel) (BinOp - (Var n$2) (Int 1))]) (Var n$2))))))))
(Axiom
  (BinOp =>
    (App $ok$tri$1 [])
    (Forall
      [(VarDecl $fuel $Fuel) (VarDecl n$2 int)]
      [(Trigger [(App tri$1 [(Var $fuel) (Var n$2)])])]
      (BinOp <= (Int 0) (App tri$1 [(Var $fuel) (Var n$2)])))))
(Axiom
  (BinOp =>
    (App $ok$double$4 [])
    (Forall
      [(VarDecl $fuel $Fuel) (VarDecl n$5 int)]
      [(Trigger [(App double$4 [(App $succ [(Var $fuel)]) (Var n$5)])])]
      (BinOp =>
        (BinOp <= (Int 0) (Var n$5))
        (BinOp ==
          (App double$4 [(App $succ [(Var $fuel)]) (Var n$5)])
          (Let d$7 (BinOp + (Var n$5) (Var n$5)) (Var d$7)))))))

(Unit tri$1 linear
  [(VarDecl n$2 int)]
  [(Assume 1 (App $ok$double$4 []))
   (Assume 2 (BinOp <= (Int 0) (Var n$2)))
   (Block body
     [(Branch (BinOp == (Var n$2) (Int 0)) [(Check 1 (BinOp <= (Int 0) (Int 0))) (Exit body)] [])
      (Check 2 (BinOp <= (Int 0) (BinOp - (Var n$2) (Int 1))))
      (Check 3
        (BinOp and (BinOp <= (Int 0) (Var n$2)) (BinOp < (BinOp - (Var n$2) (Int 1)) (Var n$2))))
      (Assume 3
        (BinOp <= (Int 0) (App tri$1 [(App $succ [(App $zero [])]) (BinOp - (Var n$2) (Int 1))])))
      (Check 4
        (BinOp <=
          (Int 0)
          (BinOp +
            (App tri$1 [(App $succ [(App $zero [])]) (BinOp - (Var n$2) (Int 1))])
            (Var n$2))))
      (Exit body)])])
(Unit double$4 linear
  [(VarDecl n$5 int) (VarDecl d$7 int)]
  [(Assume 4 (App $ok$tri$1 []))
   (Assume 5 (BinOp <= (Int 0) (Var n$5)))
   (Block body [(Assign d$7 (BinOp + (Var n$5) (Var n$5))) (Exit body)])])
(Unit step$8 linear
  [(VarDecl n$9 int)]
  [(Assume 6 (App $ok$tri$1 []))
   (Assume 7 (App $ok$double$4 []))
   (Assume 8 (BinOp <= (Int 0) (Var n$9)))
   (Assume 9 (BinOp > (Var n$9) (Int 0)))
   (Block body
     [(Check 5
        (BinOp ==
          (App tri$1 [(App $succ [(App $zero [])]) (Var n$9)])
          (BinOp +
            (App tri$1 [(App $succ [(App $zero [])]) (BinOp - (Var n$9) (Int 1))])
            (Var n$9))))])])
(Unit f$10 linear
  [(VarDecl m$11 int) (VarDecl g$12 int) (VarDecl $t1 int) (VarDecl i$13 int)]
  [(Assume 10 (App $ok$tri$1 []))
   (Assume 11 (App $ok$double$4 []))
   (Assume 12
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var m$11))
       (BinOp <= (Var m$11) (Int 9007199254740992))))
   (Assume 13 (BinOp and (BinOp >= (Var m$11) (Int 1)) (BinOp <= (Var m$11) (Int 10))))
   (Block body
     [(Assign g$12 (BinOp + (Var m$11) (Int 1)))
      (Check 6 (BinOp <= (Int 0) (Var m$11)))
      (Check 7 (BinOp > (Var m$11) (Int 0)))
      (Assume 14
        (BinOp ==
          (App tri$1 [(App $succ [(App $succ [(App $zero [])])]) (Var m$11)])
          (BinOp +
            (App tri$1 [(App $succ [(App $succ [(App $zero [])])]) (BinOp - (Var m$11) (Int 1))])
            (Var m$11))))
      (Assign $t1 (Var g$12))
      (Branch
        (BinOp <= (Int 1) (Var $t1))
        [(Assign i$13 (Int 1))
         (Check 8
           (BinOp and
             (BinOp <= (Int 1) (Var i$13))
             (BinOp <= (Var i$13) (BinOp + (Var $t1) (Int 1)))))
         (Block loop$1
           [(Havoc i$13)
            (Assume 15
              (BinOp and
                (BinOp <= (Int 1) (Var i$13))
                (BinOp <= (Var i$13) (BinOp + (Var $t1) (Int 1)))))
            (Branch
              (BinOp <= (Var i$13) (Var $t1))
              [(Assign i$13 (BinOp + (Var i$13) (Int 1)))
               (Check 9
                 (BinOp and
                   (BinOp <= (Int 1) (Var i$13))
                   (BinOp <= (Var i$13) (BinOp + (Var $t1) (Int 1)))))
               (Assume 16 (Bool false))]
              [])])]
        [])
      (Check 10 (BinOp <= (Int 0) (Int 1)))
      (Check 11
        (BinOp == (App tri$1 [(App $succ [(App $succ [(App $zero [])])]) (Int 1)]) (Int 1)))])])

(obligation 1 :kind nat :node 12)
(obligation 2 :kind nat :node 20)
(obligation 3 :kind decrease :node 21 :clause 6)
(obligation 4 :kind nat :node 23)
(obligation 5 :kind post :node 66 :clause 62)
(obligation 6 :kind nat :node 89)
(obligation 7 :kind pre :node 90 :clause 50)
(obligation 8 :kind invariant_entry :node 96)
(obligation 9 :kind invariant_preserved :node 96)
(obligation 10 :kind nat :node 99)
(obligation 11 :kind assert :node 103)

(assumption 1 :kind definition :node 26)
(assumption 2 :kind type_fact :node 8)
(assumption 3 :kind callee_post :node 21)
(assumption 4 :kind definition :node 42)
(assumption 5 :kind type_fact :node 33)
(assumption 6 :kind definition :node 66)
(assumption 7 :kind definition :node 66)
(assumption 8 :kind precondition :node 64)
(assumption 9 :kind precondition :node 50)
(assumption 10 :kind definition :node 105)
(assumption 11 :kind definition :node 105)
(assumption 12 :kind trusted :node 81 :decl 105)
(assumption 13 :kind trusted :node 79 :decl 105)
(assumption 14 :kind callee_post :node 90)
(assumption 15 :kind invariant :node 96)
(assumption 16 :kind back_edge :node 96)
