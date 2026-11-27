(FunDecl sign$1 [(VarDecl n$2 int)] int)
(FunDecl $ok$sign$1 [] bool)
(FunDecl clamp$4 [(VarDecl n$5 int)] int)
(FunDecl $ok$clamp$4 [] bool)
(FunDecl pred$10 [(VarDecl n$11 int)] int)
(FunDecl $ok$pred$10 [] bool)
(FunDecl pred_abs$13 [(VarDecl n$14 int)] int)
(FunDecl $ok$pred_abs$13 [] bool)
(FunDecl pred_nat$16 [(VarDecl n$17 int)] int)
(FunDecl $ok$pred_nat$16 [] bool)
(Axiom
  (BinOp =>
    (App $ok$sign$1 [])
    (Forall
      [(VarDecl n$2 int)]
      [(Trigger [(App sign$1 [(Var n$2)])])]
      (BinOp == (App sign$1 [(Var n$2)]) (Ite (BinOp > (Var n$2) (Int 0)) (Int 1) (Int 0))))))
(Axiom
  (BinOp =>
    (App $ok$clamp$4 [])
    (Forall
      [(VarDecl n$5 int)]
      [(Trigger [(App clamp$4 [(Var n$5)])])]
      (BinOp ==
        (App clamp$4 [(Var n$5)])
        (Let lo$7
          (Int 0)
          (Ite
            (BinOp < (Var n$5) (Var lo$7))
            (Var lo$7)
            (Ite
              (BinOp > (Var n$5) (Int 10))
              (Let hi$8 (Int 10) (Var hi$8))
              (Let m$9 (Var n$5) (Var m$9)))))))))
(Axiom
  (BinOp =>
    (App $ok$pred$10 [])
    (Forall
      [(VarDecl n$11 int)]
      [(Trigger [(App pred$10 [(Var n$11)])])]
      (BinOp =>
        (BinOp <= (Int 0) (Var n$11))
        (BinOp == (App pred$10 [(Var n$11)]) (BinOp - (Var n$11) (Int 1)))))))
(Axiom
  (BinOp =>
    (App $ok$pred_abs$13 [])
    (Forall
      [(VarDecl n$14 int)]
      [(Trigger [(App pred_abs$13 [(Var n$14)])])]
      (BinOp ==
        (App pred_abs$13 [(Var n$14)])
        (Ite
          (BinOp < (Var n$14) (Int 0))
          (App pred$10 [(BinOp - (Int 0) (Var n$14))])
          (App pred$10 [(Var n$14)]))))))
(Axiom
  (BinOp =>
    (App $ok$pred_nat$16 [])
    (Forall
      [(VarDecl n$17 int)]
      [(Trigger [(App pred_nat$16 [(Var n$17)])])]
      (BinOp =>
        (BinOp <= (Int 0) (Var n$17))
        (BinOp == (App pred_nat$16 [(Var n$17)]) (App pred$10 [(Var n$17)]))))))

(Unit sign$1 linear
  [(VarDecl n$2 int)]
  [(Assume 1 (App $ok$clamp$4 []))
   (Assume 2 (App $ok$pred$10 []))
   (Assume 3 (App $ok$pred_abs$13 []))
   (Assume 4 (App $ok$pred_nat$16 []))
   (Block body [(Branch (BinOp > (Var n$2) (Int 0)) [(Exit body)] [(Exit body)])])])
(Unit clamp$4 linear
  [(VarDecl n$5 int) (VarDecl lo$7 int) (VarDecl hi$8 int) (VarDecl m$9 int)]
  [(Assume 5 (App $ok$sign$1 []))
   (Assume 6 (App $ok$pred$10 []))
   (Assume 7 (App $ok$pred_abs$13 []))
   (Assume 8 (App $ok$pred_nat$16 []))
   (Block body
     [(Assign lo$7 (Int 0))
      (Branch
        (BinOp < (Var n$5) (Var lo$7))
        [(Exit body)]
        [(Branch
           (BinOp > (Var n$5) (Int 10))
           [(Assign hi$8 (Int 10)) (Exit body)]
           [(Assign m$9 (Var n$5)) (Exit body)])])])])
(Unit pred$10 linear
  [(VarDecl n$11 int)]
  [(Assume 9 (App $ok$sign$1 []))
   (Assume 10 (App $ok$clamp$4 []))
   (Assume 11 (App $ok$pred_abs$13 []))
   (Assume 12 (App $ok$pred_nat$16 []))
   (Assume 13 (BinOp <= (Int 0) (Var n$11)))
   (Block body [(Exit body)])])
(Unit pred_abs$13 linear
  [(VarDecl n$14 int)]
  [(Assume 14 (App $ok$sign$1 []))
   (Assume 15 (App $ok$clamp$4 []))
   (Assume 16 (App $ok$pred$10 []))
   (Assume 17 (App $ok$pred_nat$16 []))
   (Block body
     [(Branch
        (BinOp < (Var n$14) (Int 0))
        [(Check 1 (BinOp <= (Int 0) (BinOp - (Int 0) (Var n$14)))) (Exit body)]
        [])
      (Check 2 (BinOp <= (Int 0) (Var n$14)))
      (Exit body)])])
(Unit pred_nat$16 linear
  [(VarDecl n$17 int)]
  [(Assume 18 (App $ok$sign$1 []))
   (Assume 19 (App $ok$clamp$4 []))
   (Assume 20 (App $ok$pred$10 []))
   (Assume 21 (App $ok$pred_abs$13 []))
   (Assume 22 (BinOp <= (Int 0) (Var n$17)))
   (Block body [(Exit body)])])
(Unit nonneg$19 linear
  [(VarDecl k$20 int)]
  [(Assume 23 (App $ok$sign$1 []))
   (Assume 24 (App $ok$clamp$4 []))
   (Assume 25 (App $ok$pred$10 []))
   (Assume 26 (App $ok$pred_abs$13 []))
   (Assume 27 (App $ok$pred_nat$16 []))
   (Assume 28
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var k$20))
       (BinOp <= (Var k$20) (Int 9007199254740992))))
   (Block body [(Check 3 (BinOp >= (App sign$1 [(Var k$20)]) (Int 0)))])])
(Unit main$1 linear
  [(VarDecl g$21 int)]
  [(Assume 29 (App $ok$sign$1 []))
   (Assume 30 (App $ok$clamp$4 []))
   (Assume 31 (App $ok$pred$10 []))
   (Assume 32 (App $ok$pred_abs$13 []))
   (Assume 33 (App $ok$pred_nat$16 []))
   (Assign g$21 (Int 2))
   (Check 4
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var g$21))
       (BinOp <= (Var g$21) (Int 9007199254740992))))
   (Assume 34 (BinOp >= (App sign$1 [(Var g$21)]) (Int 0)))])

(obligation 1 :kind nat :node 84)
(obligation 2 :kind nat :node 91)
(obligation 3 :kind post :node 122 :clause 118)
(obligation 4 :kind range :node 130)

(assumption 1 :kind definition :node 20)
(assumption 2 :kind definition :node 20)
(assumption 3 :kind definition :node 20)
(assumption 4 :kind definition :node 20)
(assumption 5 :kind definition :node 57)
(assumption 6 :kind definition :node 57)
(assumption 7 :kind definition :node 57)
(assumption 8 :kind definition :node 57)
(assumption 9 :kind definition :node 71)
(assumption 10 :kind definition :node 71)
(assumption 11 :kind definition :node 71)
(assumption 12 :kind definition :node 71)
(assumption 13 :kind type_fact :node 65)
(assumption 14 :kind definition :node 95)
(assumption 15 :kind definition :node 95)
(assumption 16 :kind definition :node 95)
(assumption 17 :kind definition :node 95)
(assumption 18 :kind definition :node 108)
(assumption 19 :kind definition :node 108)
(assumption 20 :kind definition :node 108)
(assumption 21 :kind definition :node 108)
(assumption 22 :kind type_fact :node 102)
(assumption 23 :kind definition :node 122)
(assumption 24 :kind definition :node 122)
(assumption 25 :kind definition :node 122)
(assumption 26 :kind definition :node 122)
(assumption 27 :kind definition :node 122)
(assumption 28 :kind precondition :node 120)
(assumption 29 :kind definition :node 133)
(assumption 30 :kind definition :node 133)
(assumption 31 :kind definition :node 133)
(assumption 32 :kind definition :node 133)
(assumption 33 :kind definition :node 133)
(assumption 34 :kind callee_post :node 131)
