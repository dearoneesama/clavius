(FunDecl sign$1 [(VarDecl n$2 int)] int)
(FunDecl $ok$sign$1 [] bool)
(FunDecl clamp$4 [(VarDecl n$5 int)] int)
(FunDecl $ok$clamp$4 [] bool)
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

(Unit sign$1 linear
  [(VarDecl n$2 int)]
  [(Assume 1 (App $ok$clamp$4 []))
   (Block body [(Branch (BinOp > (Var n$2) (Int 0)) [(Exit body)] [(Exit body)])])])
(Unit clamp$4 linear
  [(VarDecl n$5 int) (VarDecl lo$7 int) (VarDecl hi$8 int) (VarDecl m$9 int)]
  [(Assume 2 (App $ok$sign$1 []))
   (Block body
     [(Assign lo$7 (Int 0))
      (Branch
        (BinOp < (Var n$5) (Var lo$7))
        [(Exit body)]
        [(Branch
           (BinOp > (Var n$5) (Int 10))
           [(Assign hi$8 (Int 10)) (Exit body)]
           [(Assign m$9 (Var n$5)) (Exit body)])])])])
(Unit nonneg$10 linear
  [(VarDecl k$11 int)]
  [(Assume 3 (App $ok$sign$1 []))
   (Assume 4 (App $ok$clamp$4 []))
   (Assume 5
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var k$11))
       (BinOp <= (Var k$11) (Int 9007199254740992))))
   (Block body [(Check 1 (BinOp >= (App sign$1 [(Var k$11)]) (Int 0)))])])
(Unit main$1 linear
  [(VarDecl g$12 int)]
  [(Assume 6 (App $ok$sign$1 []))
   (Assume 7 (App $ok$clamp$4 []))
   (Assign g$12 (Int 2))
   (Check 2
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var g$12))
       (BinOp <= (Var g$12) (Int 9007199254740992))))
   (Assume 8 (BinOp >= (App sign$1 [(Var g$12)]) (Int 0)))])

(obligation 1 :kind post :node 71 :clause 67)
(obligation 2 :kind range :node 79)

(assumption 1 :kind definition :node 20)
(assumption 2 :kind definition :node 57)
(assumption 3 :kind definition :node 71)
(assumption 4 :kind definition :node 71)
(assumption 5 :kind precondition :node 69)
(assumption 6 :kind definition :node 82)
(assumption 7 :kind definition :node 82)
(assumption 8 :kind callee_post :node 80)
