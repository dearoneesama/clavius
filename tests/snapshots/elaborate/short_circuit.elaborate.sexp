(Unit main$1
  [(VarDecl x$1 int)
   (VarDecl p$2 bool)
   (VarDecl $t1 bool)
   (VarDecl q$3 bool)
   (VarDecl $t2 bool)
   (VarDecl r$4 bool)
   (VarDecl s$5 bool)]
  [(Assign x$1 (Int 1))
   (Assign p$2 (BinOp and (BinOp > (Var x$1) (Int 0)) (BinOp < (Var x$1) (Int 2))))
   (Branch
     (BinOp > (Var x$1) (Int 0))
     [(Check 1
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp + (Var x$1) (Int 1)))
          (BinOp <= (BinOp + (Var x$1) (Int 1)) (Int 9007199254740992))))
      (Assign $t1 (BinOp > (BinOp + (Var x$1) (Int 1)) (Int 0)))]
     [(Assign $t1 (Bool false))])
   (Assign q$3 (Var $t1))
   (Branch
     (BinOp > (Var x$1) (Int 0))
     [(Assign $t2 (Bool true))]
     [(Check 2
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp - (Var x$1) (Int 1)))
          (BinOp <= (BinOp - (Var x$1) (Int 1)) (Int 9007199254740992))))
      (Assign $t2 (BinOp > (BinOp - (Var x$1) (Int 1)) (Int 0)))])
   (Assign r$4 (Var $t2))
   (Assign s$5 (Not (BinOp or (Var p$2) (Var q$3))))])

(obligation 1 :kind range :node 18)
(obligation 2 :kind range :node 29)
