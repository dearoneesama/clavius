(SortDecl $Fuel)
(FunDecl $zero [] $Fuel)
(FunDecl $succ [(VarDecl $fuel $Fuel)] $Fuel)
(FunDecl tri$1 [(VarDecl $fuel $Fuel) (VarDecl n$2 int)] int)
(FunDecl $ok$tri$1 [] bool)
(FunDecl p$4 [(VarDecl i$5 int)] bool)
(FunDecl $ok$p$4 [] bool)
(FunDecl p_upto$7 [(VarDecl n$8 int)] bool)
(FunDecl $ok$p_upto$7 [] bool)
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
    (App $ok$p$4 [])
    (Forall
      [(VarDecl i$5 int)]
      [(Trigger [(App p$4 [(Var i$5)])])]
      (BinOp == (App p$4 [(Var i$5)]) (BinOp > (Var i$5) (Int 0))))))
(Axiom
  (BinOp =>
    (App $ok$p_upto$7 [])
    (Forall
      [(VarDecl n$8 int)]
      [(Trigger [(App p_upto$7 [(Var n$8)])])]
      (BinOp ==
        (App p_upto$7 [(Var n$8)])
        (Forall
          [(VarDecl i$10 int)]
          [(Trigger [(App p$4 [(Var i$10)])])]
          (BinOp =>
            (BinOp and (BinOp <= (Int 0) (Var i$10)) (BinOp < (Var i$10) (Var n$8)))
            (App p$4 [(Var i$10)])))))))

(Unit tri$1 linear
  [(VarDecl n$2 int)]
  [(Assume 1 (App $ok$p$4 []))
   (Assume 2 (App $ok$p_upto$7 []))
   (Assume 3 (BinOp <= (Int 0) (Var n$2)))
   (Block body
     [(Branch (BinOp == (Var n$2) (Int 0)) [(Check 1 (BinOp <= (Int 0) (Int 0))) (Exit body)] [])
      (Check 2 (BinOp <= (Int 0) (BinOp - (Var n$2) (Int 1))))
      (Check 3
        (BinOp and (BinOp <= (Int 0) (Var n$2)) (BinOp < (BinOp - (Var n$2) (Int 1)) (Var n$2))))
      (Assume 4
        (BinOp <= (Int 0) (App tri$1 [(App $succ [(App $zero [])]) (BinOp - (Var n$2) (Int 1))])))
      (Check 4
        (BinOp <=
          (Int 0)
          (BinOp +
            (App tri$1 [(App $succ [(App $zero [])]) (BinOp - (Var n$2) (Int 1))])
            (Var n$2))))
      (Exit body)])])
(Unit p$4 linear
  [(VarDecl i$5 int)]
  [(Assume 5 (App $ok$tri$1 [])) (Assume 6 (App $ok$p_upto$7 [])) (Block body [(Exit body)])])
(Unit p_upto$7 linear
  [(VarDecl n$8 int)]
  [(Assume 7 (App $ok$tri$1 [])) (Assume 8 (App $ok$p$4 [])) (Block body [(Exit body)])])
(Unit at$11 linear
  [(VarDecl n$12 int) (VarDecl k$17 int) (VarDecl $t1 int) (VarDecl m$19 int) (VarDecl $t2 bool)]
  [(Assume 9 (App $ok$tri$1 []))
   (Assume 10 (App $ok$p$4 []))
   (Assume 11 (App $ok$p_upto$7 []))
   (Assume 12
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$12))
       (BinOp <= (Var n$12) (Int 9007199254740992))))
   (Assume 13 (BinOp and (BinOp >= (Var n$12) (Int 0)) (BinOp <= (Var n$12) (Int 100))))
   (Assume 14
     (Forall
       [(VarDecl i$13 int) (VarDecl j$14 int)]
       [(Trigger
          [(App tri$1 [(App $succ [(App $zero [])]) (Var i$13)])
           (App tri$1 [(App $succ [(App $zero [])]) (Var j$14)])])]
       (Let d$15
         (App tri$1 [(App $succ [(App $zero [])]) (Var i$13)])
         (BinOp =>
           (BinOp <= (Var i$13) (Var j$14))
           (BinOp <= (Var d$15) (App tri$1 [(App $succ [(App $zero [])]) (Var j$14)]))))))
   (Block body
     [(Assign k$17 (Int 0))
      (Check 5 (BinOp and (BinOp <= (Int 0) (Var k$17)) (BinOp <= (Var k$17) (Var n$12))))
      (Check 6
        (Forall
          [(VarDecl i$18 int)]
          [(Trigger [(App p$4 [(Var i$18)])])]
          (BinOp =>
            (BinOp and (BinOp <= (Int 0) (Var i$18)) (BinOp < (Var i$18) (Var k$17)))
            (App p$4 [(Var i$18)]))))
      (Block loop$1
        [(Havoc k$17)
         (Assume 15
           (BinOp and
             (BinOp <= (Int -9007199254740992) (Var k$17))
             (BinOp <= (Var k$17) (Int 9007199254740992))))
         (Assume 16 (BinOp and (BinOp <= (Int 0) (Var k$17)) (BinOp <= (Var k$17) (Var n$12))))
         (Assume 17
           (Forall
             [(VarDecl i$18 int)]
             [(Trigger [(App p$4 [(Var i$18)])])]
             (BinOp =>
               (BinOp and (BinOp <= (Int 0) (Var i$18)) (BinOp < (Var i$18) (Var k$17)))
               (App p$4 [(Var i$18)]))))
         (Assign $t1 (BinOp - (Var n$12) (Var k$17)))
         (Branch
           (BinOp < (Var k$17) (Var n$12))
           [(Assume 18 (App p$4 [(Var k$17)]))
            (Check 7
              (BinOp and
                (BinOp <= (Int -9007199254740992) (BinOp + (Var k$17) (Int 1)))
                (BinOp <= (BinOp + (Var k$17) (Int 1)) (Int 9007199254740992))))
            (Assign k$17 (BinOp + (Var k$17) (Int 1)))
            (Check 8 (BinOp and (BinOp <= (Int 0) (Var k$17)) (BinOp <= (Var k$17) (Var n$12))))
            (Check 9
              (Forall
                [(VarDecl i$18 int)]
                [(Trigger [(App p$4 [(Var i$18)])])]
                (BinOp =>
                  (BinOp and (BinOp <= (Int 0) (Var i$18)) (BinOp < (Var i$18) (Var k$17)))
                  (App p$4 [(Var i$18)]))))
            (Check 10
              (BinOp and
                (BinOp <= (Int 0) (Var $t1))
                (BinOp < (BinOp - (Var n$12) (Var k$17)) (Var $t1))))
            (Assume 19 (Bool false))]
           [])])
      (Assign m$19 (BinOp - (Var k$17) (Int 5)))
      (Branch
        (BinOp >= (Var m$19) (Int 0))
        [(Check 11 (BinOp <= (Int 0) (Var m$19)))
         (Assign $t2 (BinOp >= (App tri$1 [(App $succ [(App $zero [])]) (Var m$19)]) (Int 0)))]
        [(Assign $t2 (Bool true))])
      (Check 12 (Var $t2))
      (Check 13
        (Forall
          [(VarDecl i$20 int)]
          [(Trigger [(App p$4 [(Var i$20)])])]
          (Forall
            [(VarDecl j$21 int)]
            [(Trigger [(App p$4 [(Var j$21)])])]
            (BinOp =>
              (BinOp and (App p$4 [(Var i$20)]) (BinOp < (Var i$20) (Var j$21)))
              (App p$4 [(Var j$21)])))))
      (Check 14
        (Exists
          [(VarDecl i$16 int)]
          [(Trigger [(App tri$1 [(App $succ [(App $zero [])]) (Var i$16)])])]
          (BinOp ==
            (App tri$1 [(App $succ [(App $zero [])]) (Var i$16)])
            (App tri$1 [(App $succ [(App $zero [])]) (Var n$12)]))))])])

(obligation 1 :kind nat :node 12)
(obligation 2 :kind nat :node 20)
(obligation 3 :kind decrease :node 21 :clause 6)
(obligation 4 :kind nat :node 23)
(obligation 5 :kind invariant_entry :node 166 :clause 129)
(obligation 6 :kind invariant_entry :node 166 :clause 148)
(obligation 7 :kind range :node 163)
(obligation 8 :kind invariant_preserved :node 166 :clause 129)
(obligation 9 :kind invariant_preserved :node 166 :clause 148)
(obligation 10 :kind decrease :node 166 :clause 152)
(obligation 11 :kind nat :node 178)
(obligation 12 :kind assert :node 183)
(obligation 13 :kind assert :node 209)
(obligation 14 :kind post :node 212 :clause 116)

(assumption 1 :kind definition :node 26)
(assumption 2 :kind definition :node 26)
(assumption 3 :kind type_fact :node 8)
(assumption 4 :kind callee_post :node 21)
(assumption 5 :kind definition :node 39)
(assumption 6 :kind definition :node 39)
(assumption 7 :kind definition :node 67)
(assumption 8 :kind definition :node 67)
(assumption 9 :kind definition :node 212)
(assumption 10 :kind definition :node 212)
(assumption 11 :kind definition :node 212)
(assumption 12 :kind trusted :node 118 :decl 212)
(assumption 13 :kind trusted :node 79 :decl 212)
(assumption 14 :kind trusted :node 102 :decl 212)
(assumption 15 :kind type_fact :node 166)
(assumption 16 :kind invariant :node 129)
(assumption 17 :kind invariant :node 148)
(assumption 18 :kind assumed :node 159)
(assumption 19 :kind back_edge :node 166)
