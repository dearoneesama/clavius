(SortDecl $Fuel)
(FunDecl $zero [] $Fuel)
(FunDecl $succ [(VarDecl $fuel $Fuel)] $Fuel)
(FunDecl sign$1 [(VarDecl $fuel $Fuel) (VarDecl n$2 int)] int)
(FunDecl $ok$sign$1 [] bool)
(Axiom
  (BinOp =>
    (App $ok$sign$1 [])
    (Forall
      [(VarDecl $fuel $Fuel) (VarDecl n$2 int)]
      [(Trigger [(App sign$1 [(App $succ [(Var $fuel)]) (Var n$2)])])]
      (BinOp ==
        (App sign$1 [(App $succ [(Var $fuel)]) (Var n$2)])
        (Ite (BinOp > (Var n$2) (Int 0)) (Int 1) (Int 0))))))

(Unit sign$1
  [(VarDecl n$2 int)]
  [(Block body [(Branch (BinOp > (Var n$2) (Int 0)) [(Exit body)] [(Exit body)])])])
(Unit nonneg$4
  [(VarDecl k$5 int)]
  [(Assume 1 (App $ok$sign$1 []))
   (Assume 2
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var k$5))
       (BinOp <= (Var k$5) (Int 9007199254740992))))
   (Block body
     [(Check 1 (BinOp >= (App sign$1 [(App $succ [(App $zero [])]) (Var k$5)]) (Int 0)))])])
(Unit main$1
  [(VarDecl g$6 int)]
  [(Assume 3 (App $ok$sign$1 []))
   (Assign g$6 (Int 2))
   (Check 2
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var g$6))
       (BinOp <= (Var g$6) (Int 9007199254740992))))
   (Assume 4 (BinOp >= (App sign$1 [(App $succ [(App $zero [])]) (Var g$6)]) (Int 0)))])

(obligation 1 :kind post :node 34 :clause 30)
(obligation 2 :kind range :node 42)

(assumption 1 :kind definition :node 34)
(assumption 2 :kind precondition :node 32)
(assumption 3 :kind definition :node 45)
(assumption 4 :kind callee_post :node 43)
