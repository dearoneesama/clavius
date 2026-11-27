(SortDecl $Fuel)
(FunDecl $zero [] $Fuel)
(FunDecl $succ [(VarDecl $fuel $Fuel)] $Fuel)
(FunDecl tri$1 [(VarDecl $fuel $Fuel) (VarDecl n$2 int)] int)
(FunDecl $ok$tri$1 [] bool)
(FunDecl p$4 [(VarDecl i$5 int)] bool)
(FunDecl $ok$p$4 [] bool)
(FunDecl tri_ge$7 [(VarDecl n$8 int)] bool)
(FunDecl $ok$tri_ge$7 [] bool)
(FunDecl even$10 [(VarDecl $fuel $Fuel) (VarDecl n$11 int)] bool)
(FunDecl $ok$even$10 [] bool)
(FunDecl p_upto$13 [(VarDecl n$14 int)] bool)
(FunDecl $ok$p_upto$13 [] bool)
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
    (App $ok$tri_ge$7 [])
    (Forall
      [(VarDecl n$8 int)]
      [(Trigger [(App tri_ge$7 [(Var n$8)])])]
      (BinOp =>
        (BinOp <= (Int 0) (Var n$8))
        (BinOp ==
          (App tri_ge$7 [(Var n$8)])
          (BinOp >= (App tri$1 [(App $succ [(App $zero [])]) (Var n$8)]) (Var n$8)))))))
(Axiom
  (BinOp =>
    (App $ok$even$10 [])
    (Forall
      [(VarDecl $fuel $Fuel) (VarDecl n$11 int)]
      [(Trigger [(App even$10 [(App $succ [(Var $fuel)]) (Var n$11)])])]
      (BinOp ==
        (App even$10 [(App $succ [(Var $fuel)]) (Var n$11)])
        (App even$10 [(Var $fuel) (Var n$11)])))))
(Axiom
  (BinOp =>
    (App $ok$even$10 [])
    (Forall
      [(VarDecl $fuel $Fuel) (VarDecl n$11 int)]
      [(Trigger [(App even$10 [(App $succ [(Var $fuel)]) (Var n$11)])])]
      (BinOp =>
        (BinOp <= (Int 0) (Var n$11))
        (BinOp ==
          (App even$10 [(App $succ [(Var $fuel)]) (Var n$11)])
          (Ite
            (BinOp == (Var n$11) (Int 0))
            (Bool true)
            (Not (App even$10 [(Var $fuel) (BinOp - (Var n$11) (Int 1))]))))))))
(Axiom
  (BinOp =>
    (App $ok$p_upto$13 [])
    (Forall
      [(VarDecl n$14 int)]
      [(Trigger [(App p_upto$13 [(Var n$14)])])]
      (BinOp ==
        (App p_upto$13 [(Var n$14)])
        (Forall
          [(VarDecl i$16 int)]
          [(Trigger [(App p$4 [(Var i$16)])])]
          (BinOp =>
            (BinOp and (BinOp <= (Int 0) (Var i$16)) (BinOp < (Var i$16) (Var n$14)))
            (App p$4 [(Var i$16)])))))))

(Unit tri$1 linear
  [(VarDecl n$2 int)]
  [(Assume 1 (App $ok$p$4 []))
   (Assume 2 (App $ok$tri_ge$7 []))
   (Assume 3 (App $ok$even$10 []))
   (Assume 4 (App $ok$p_upto$13 []))
   (Assume 5 (BinOp <= (Int 0) (Var n$2)))
   (Block body
     [(Branch (BinOp == (Var n$2) (Int 0)) [(Check 1 (BinOp <= (Int 0) (Int 0))) (Exit body)] [])
      (Check 2 (BinOp <= (Int 0) (BinOp - (Var n$2) (Int 1))))
      (Check 3
        (BinOp and (BinOp <= (Int 0) (Var n$2)) (BinOp < (BinOp - (Var n$2) (Int 1)) (Var n$2))))
      (Assume 6
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
  [(Assume 7 (App $ok$tri$1 []))
   (Assume 8 (App $ok$tri_ge$7 []))
   (Assume 9 (App $ok$even$10 []))
   (Assume 10 (App $ok$p_upto$13 []))
   (Block body [(Exit body)])])
(Unit tri_ge$7 linear
  [(VarDecl n$8 int)]
  [(Assume 11 (App $ok$tri$1 []))
   (Assume 12 (App $ok$p$4 []))
   (Assume 13 (App $ok$even$10 []))
   (Assume 14 (App $ok$p_upto$13 []))
   (Assume 15 (BinOp <= (Int 0) (Var n$8)))
   (Block body [(Exit body)])])
(Unit even$10 linear
  [(VarDecl n$11 int)]
  [(Assume 16 (App $ok$tri$1 []))
   (Assume 17 (App $ok$p$4 []))
   (Assume 18 (App $ok$tri_ge$7 []))
   (Assume 19 (App $ok$p_upto$13 []))
   (Assume 20 (BinOp <= (Int 0) (Var n$11)))
   (Block body
     [(Branch (BinOp == (Var n$11) (Int 0)) [(Exit body)] [])
      (Check 5 (BinOp <= (Int 0) (BinOp - (Var n$11) (Int 1))))
      (Check 6
        (BinOp and (BinOp <= (Int 0) (Var n$11)) (BinOp < (BinOp - (Var n$11) (Int 1)) (Var n$11))))
      (Exit body)])])
(Unit p_upto$13 linear
  [(VarDecl n$14 int)]
  [(Assume 21 (App $ok$tri$1 []))
   (Assume 22 (App $ok$p$4 []))
   (Assume 23 (App $ok$tri_ge$7 []))
   (Assume 24 (App $ok$even$10 []))
   (Block body [(Exit body)])])
(Unit at$17 linear
  [(VarDecl n$18 int) (VarDecl k$23 int) (VarDecl $t1 int) (VarDecl m$25 int) (VarDecl $t2 bool)]
  [(Assume 25 (App $ok$tri$1 []))
   (Assume 26 (App $ok$p$4 []))
   (Assume 27 (App $ok$tri_ge$7 []))
   (Assume 28 (App $ok$even$10 []))
   (Assume 29 (App $ok$p_upto$13 []))
   (Assume 30
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$18))
       (BinOp <= (Var n$18) (Int 9007199254740992))))
   (Assume 31 (BinOp and (BinOp >= (Var n$18) (Int 0)) (BinOp <= (Var n$18) (Int 100))))
   (Assume 32
     (Forall
       [(VarDecl i$19 int) (VarDecl j$20 int)]
       [(Trigger
          [(App tri$1 [(App $succ [(App $zero [])]) (Var i$19)])
           (App tri$1 [(App $succ [(App $zero [])]) (Var j$20)])])]
       (Let d$21
         (App tri$1 [(App $succ [(App $zero [])]) (Var i$19)])
         (BinOp =>
           (BinOp <= (Var i$19) (Var j$20))
           (BinOp <= (Var d$21) (App tri$1 [(App $succ [(App $zero [])]) (Var j$20)]))))))
   (Block body
     [(Assign k$23 (Int 0))
      (Check 7 (BinOp and (BinOp <= (Int 0) (Var k$23)) (BinOp <= (Var k$23) (Var n$18))))
      (Check 8
        (Forall
          [(VarDecl i$24 int)]
          [(Trigger [(App p$4 [(Var i$24)])])]
          (BinOp =>
            (BinOp and (BinOp <= (Int 0) (Var i$24)) (BinOp < (Var i$24) (Var k$23)))
            (App p$4 [(Var i$24)]))))
      (Block loop$1
        [(Havoc k$23)
         (Assume 33
           (BinOp and
             (BinOp <= (Int -9007199254740992) (Var k$23))
             (BinOp <= (Var k$23) (Int 9007199254740992))))
         (Assume 34 (BinOp and (BinOp <= (Int 0) (Var k$23)) (BinOp <= (Var k$23) (Var n$18))))
         (Assume 35
           (Forall
             [(VarDecl i$24 int)]
             [(Trigger [(App p$4 [(Var i$24)])])]
             (BinOp =>
               (BinOp and (BinOp <= (Int 0) (Var i$24)) (BinOp < (Var i$24) (Var k$23)))
               (App p$4 [(Var i$24)]))))
         (Assign $t1 (BinOp - (Var n$18) (Var k$23)))
         (Branch
           (BinOp < (Var k$23) (Var n$18))
           [(Assume 36 (App p$4 [(Var k$23)]))
            (Check 9
              (BinOp and
                (BinOp <= (Int -9007199254740992) (BinOp + (Var k$23) (Int 1)))
                (BinOp <= (BinOp + (Var k$23) (Int 1)) (Int 9007199254740992))))
            (Assign k$23 (BinOp + (Var k$23) (Int 1)))
            (Check 10 (BinOp and (BinOp <= (Int 0) (Var k$23)) (BinOp <= (Var k$23) (Var n$18))))
            (Check 11
              (Forall
                [(VarDecl i$24 int)]
                [(Trigger [(App p$4 [(Var i$24)])])]
                (BinOp =>
                  (BinOp and (BinOp <= (Int 0) (Var i$24)) (BinOp < (Var i$24) (Var k$23)))
                  (App p$4 [(Var i$24)]))))
            (Check 12
              (BinOp and
                (BinOp <= (Int 0) (Var $t1))
                (BinOp < (BinOp - (Var n$18) (Var k$23)) (Var $t1))))
            (Assume 37 (Bool false))]
           [])])
      (Assign m$25 (BinOp - (Var k$23) (Int 5)))
      (Branch
        (BinOp >= (Var m$25) (Int 0))
        [(Check 13 (BinOp <= (Int 0) (Var m$25)))
         (Assign $t2 (BinOp >= (App tri$1 [(App $succ [(App $zero [])]) (Var m$25)]) (Int 0)))]
        [(Assign $t2 (Bool true))])
      (Check 14 (Var $t2))
      (Check 15
        (Forall
          [(VarDecl i$26 int)]
          [(Trigger [(App p$4 [(Var i$26)])])]
          (Forall
            [(VarDecl j$27 int)]
            [(Trigger [(App p$4 [(Var j$27)])])]
            (BinOp =>
              (BinOp and (App p$4 [(Var i$26)]) (BinOp < (Var i$26) (Var j$27)))
              (App p$4 [(Var j$27)])))))
      (Check 16 (BinOp <= (Int 0) (Var n$18)))
      (Check 17 (BinOp >= (App tri$1 [(App $succ [(App $zero [])]) (Var n$18)]) (Int 0)))
      (Check 18
        (Exists
          [(VarDecl i$22 int)]
          [(Trigger [(App tri$1 [(App $succ [(App $zero [])]) (Var i$22)])])]
          (BinOp ==
            (App tri$1 [(App $succ [(App $zero [])]) (Var i$22)])
            (App tri$1 [(App $succ [(App $zero [])]) (Var n$18)]))))])])
(Unit main$1 linear
  [(VarDecl $t1 bool) (VarDecl w$30 int) (VarDecl v$31 int)]
  [(Assume 38 (App $ok$tri$1 []))
   (Assume 39 (App $ok$p$4 []))
   (Assume 40 (App $ok$tri_ge$7 []))
   (Assume 41 (App $ok$even$10 []))
   (Assume 42 (App $ok$p_upto$13 []))
   (Check 19
     (Forall
       [(VarDecl i$28 int)]
       [(Trigger [(App tri$1 [(App $succ [(App $zero [])]) (Var i$28)])])]
       (BinOp =>
         (App p$4 [(Var i$28)])
         (BinOp >= (App tri$1 [(App $succ [(App $zero [])]) (Var i$28)]) (Int 0)))))
   (Branch
     (Forall
       [(VarDecl n$8 int)]
       [(Trigger [(App tri_ge$7 [(Var n$8)])])]
       (BinOp => (BinOp <= (Int 0) (Var n$8)) (App tri_ge$7 [(Var n$8)])))
     [(Check 20 (BinOp <= (Int 0) (Int 3))) (Assign $t1 (App tri_ge$7 [(Int 3)]))]
     [(Assign $t1 (Bool true))])
   (Check 21 (Var $t1))
   (Check 22 (BinOp <= (Int 0) (Int 2)))
   (Check 23
     (BinOp =>
       (App even$10 [(App $succ [(App $zero [])]) (Int 2)])
       (Exists
         [(VarDecl n$11 int)]
         [(Trigger [(App even$10 [(App $succ [(App $zero [])]) (Var n$11)])])]
         (BinOp and
           (BinOp <= (Int 0) (Var n$11))
           (App even$10 [(App $succ [(App $zero [])]) (Var n$11)])))))
   (Havoc w$30)
   (Assume 43
     (BinOp =>
       (Exists
         [(VarDecl i$29 int)]
         [(Trigger [(App p$4 [(Var i$29)])])]
         (BinOp and
           (App p$4 [(Var i$29)])
           (BinOp > (App tri$1 [(App $succ [(App $zero [])]) (Var i$29)]) (Int 3))))
       (BinOp and
         (App p$4 [(Var w$30)])
         (BinOp > (App tri$1 [(App $succ [(App $zero [])]) (Var w$30)]) (Int 3)))))
   (Havoc v$31)
   (Assume 44
     (BinOp and
       (BinOp <= (Int 0) (Var v$31))
       (BinOp =>
         (Exists
           [(VarDecl n$11 int)]
           [(Trigger [(App even$10 [(App $succ [(App $zero [])]) (Var n$11)])])]
           (BinOp and
             (BinOp <= (Int 0) (Var n$11))
             (App even$10 [(App $succ [(App $zero [])]) (Var n$11)])))
         (App even$10 [(App $succ [(App $zero [])]) (Var v$31)]))))
   (Havoc w$30)
   (Assume 45
     (BinOp =>
       (Exists [(VarDecl i$32 int)] [(Trigger [(App p$4 [(Var i$32)])])] (App p$4 [(Var i$32)]))
       (App p$4 [(Var w$30)])))])

(obligation 1 :kind nat :node 12)
(obligation 2 :kind nat :node 20)
(obligation 3 :kind decrease :node 21 :clause 6)
(obligation 4 :kind nat :node 23)
(obligation 5 :kind nat :node 75)
(obligation 6 :kind decrease :node 76 :clause 61)
(obligation 7 :kind invariant_entry :node 207 :clause 170)
(obligation 8 :kind invariant_entry :node 207 :clause 189)
(obligation 9 :kind range :node 204)
(obligation 10 :kind invariant_preserved :node 207 :clause 170)
(obligation 11 :kind invariant_preserved :node 207 :clause 189)
(obligation 12 :kind decrease :node 207 :clause 193)
(obligation 13 :kind nat :node 219)
(obligation 14 :kind assert :node 224)
(obligation 15 :kind assert :node 250)
(obligation 16 :kind nat :node 253)
(obligation 17 :kind assert :node 257)
(obligation 18 :kind post :node 259 :clause 157)
(obligation 19 :kind assert :node 279)
(obligation 20 :kind nat :node 285)
(obligation 21 :kind assert :node 288)
(obligation 22 :kind nat :node 291)
(obligation 23 :kind assert :node 297)

(assumption 1 :kind definition :node 26)
(assumption 2 :kind definition :node 26)
(assumption 3 :kind definition :node 26)
(assumption 4 :kind definition :node 26)
(assumption 5 :kind type_fact :node 8)
(assumption 6 :kind callee_post :node 21)
(assumption 7 :kind definition :node 39)
(assumption 8 :kind definition :node 39)
(assumption 9 :kind definition :node 39)
(assumption 10 :kind definition :node 39)
(assumption 11 :kind definition :node 54)
(assumption 12 :kind definition :node 54)
(assumption 13 :kind definition :node 54)
(assumption 14 :kind definition :node 54)
(assumption 15 :kind type_fact :node 46)
(assumption 16 :kind definition :node 80)
(assumption 17 :kind definition :node 80)
(assumption 18 :kind definition :node 80)
(assumption 19 :kind definition :node 80)
(assumption 20 :kind type_fact :node 63)
(assumption 21 :kind definition :node 108)
(assumption 22 :kind definition :node 108)
(assumption 23 :kind definition :node 108)
(assumption 24 :kind definition :node 108)
(assumption 25 :kind definition :node 259)
(assumption 26 :kind definition :node 259)
(assumption 27 :kind definition :node 259)
(assumption 28 :kind definition :node 259)
(assumption 29 :kind definition :node 259)
(assumption 30 :kind trusted :node 159 :decl 259)
(assumption 31 :kind trusted :node 120 :decl 259)
(assumption 32 :kind trusted :node 143 :decl 259)
(assumption 33 :kind type_fact :node 207)
(assumption 34 :kind invariant :node 170)
(assumption 35 :kind invariant :node 189)
(assumption 36 :kind assumed :node 200)
(assumption 37 :kind back_edge :node 207)
(assumption 38 :kind definition :node 332)
(assumption 39 :kind definition :node 332)
(assumption 40 :kind definition :node 332)
(assumption 41 :kind definition :node 332)
(assumption 42 :kind definition :node 332)
(assumption 43 :kind witness :node 312)
(assumption 44 :kind witness :node 317)
(assumption 45 :kind witness :node 329)
