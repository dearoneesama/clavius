(SortDecl $Fuel)
(FunDecl $zero [] $Fuel)
(FunDecl $succ [(VarDecl $fuel $Fuel)] $Fuel)
(FunDecl tri$1 [(VarDecl $fuel $Fuel) (VarDecl n$2 int)] int)
(FunDecl $ok$tri$1 [] bool)
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

(Unit tri$1
  [(VarDecl n$2 int)]
  [(Assume 1 (BinOp <= (Int 0) (Var n$2)))
   (Block body
     [(Branch (BinOp == (Var n$2) (Int 0)) [(Check 1 (BinOp <= (Int 0) (Int 0))) (Exit body)] [])
      (Check 2 (BinOp <= (Int 0) (BinOp - (Var n$2) (Int 1))))
      (Check 3
        (BinOp and (BinOp <= (Int 0) (Var n$2)) (BinOp < (BinOp - (Var n$2) (Int 1)) (Var n$2))))
      (Assume 2
        (BinOp <= (Int 0) (App tri$1 [(App $succ [(App $zero [])]) (BinOp - (Var n$2) (Int 1))])))
      (Check 4
        (BinOp <=
          (Int 0)
          (BinOp +
            (App tri$1 [(App $succ [(App $zero [])]) (BinOp - (Var n$2) (Int 1))])
            (Var n$2))))
      (Exit body)])])
(Unit step$4
  [(VarDecl n$5 int)]
  [(Assume 3 (App $ok$tri$1 []))
   (Assume 4 (BinOp <= (Int 0) (Var n$5)))
   (Assume 5 (BinOp > (Var n$5) (Int 0)))
   (Block body
     [(Check 5
        (BinOp ==
          (App tri$1 [(App $succ [(App $zero [])]) (Var n$5)])
          (BinOp +
            (App tri$1 [(App $succ [(App $zero [])]) (BinOp - (Var n$5) (Int 1))])
            (Var n$5))))])])
(Unit f$6
  [(VarDecl m$7 int) (VarDecl g$8 int) (VarDecl $t1 int) (VarDecl i$9 int)]
  [(Assume 6 (App $ok$tri$1 []))
   (Assume 7
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var m$7))
       (BinOp <= (Var m$7) (Int 9007199254740992))))
   (Assume 8 (BinOp and (BinOp >= (Var m$7) (Int 1)) (BinOp <= (Var m$7) (Int 10))))
   (Block body
     [(Assign g$8 (BinOp + (Var m$7) (Int 1)))
      (Check 6 (BinOp <= (Int 0) (Var m$7)))
      (Check 7 (BinOp > (Var m$7) (Int 0)))
      (Assume 9
        (BinOp ==
          (App tri$1 [(App $succ [(App $succ [(App $zero [])])]) (Var m$7)])
          (BinOp +
            (App tri$1 [(App $succ [(App $succ [(App $zero [])])]) (BinOp - (Var m$7) (Int 1))])
            (Var m$7))))
      (Assign $t1 (Var g$8))
      (Branch
        (BinOp <= (Int 1) (Var $t1))
        [(Assign i$9 (Int 1))
         (Check 8
           (BinOp and
             (BinOp <= (Int 1) (Var i$9))
             (BinOp <= (Var i$9) (BinOp + (Var $t1) (Int 1)))))
         (Block loop$1
           [(Havoc i$9)
            (Assume 10
              (BinOp and
                (BinOp <= (Int 1) (Var i$9))
                (BinOp <= (Var i$9) (BinOp + (Var $t1) (Int 1)))))
            (Branch
              (BinOp <= (Var i$9) (Var $t1))
              [(Assign i$9 (BinOp + (Var i$9) (Int 1)))
               (Check 9
                 (BinOp and
                   (BinOp <= (Int 1) (Var i$9))
                   (BinOp <= (Var i$9) (BinOp + (Var $t1) (Int 1)))))
               (Assume 11 (Bool false))]
              [])])]
        [])
      (Check 10 (BinOp <= (Int 0) (Int 1)))
      (Check 11
        (BinOp == (App tri$1 [(App $succ [(App $succ [(App $zero [])])]) (Int 1)]) (Int 1)))])])

(obligation 1 :kind nat :node 12)
(obligation 2 :kind nat :node 20)
(obligation 3 :kind decrease :node 21 :clause 6)
(obligation 4 :kind nat :node 23)
(obligation 5 :kind post :node 50 :clause 46)
(obligation 6 :kind nat :node 73)
(obligation 7 :kind pre :node 74 :clause 34)
(obligation 8 :kind invariant_entry :node 80)
(obligation 9 :kind invariant_preserved :node 80)
(obligation 10 :kind nat :node 83)
(obligation 11 :kind assert :node 87)

(assumption 1 :kind type_fact :node 8)
(assumption 2 :kind callee_post :node 21)
(assumption 3 :kind definition :node 50)
(assumption 4 :kind precondition :node 48)
(assumption 5 :kind precondition :node 34)
(assumption 6 :kind definition :node 89)
(assumption 7 :kind trusted :node 65 :decl 89)
(assumption 8 :kind trusted :node 63 :decl 89)
(assumption 9 :kind callee_post :node 74)
(assumption 10 :kind invariant :node 80)
(assumption 11 :kind back_edge :node 80)
