; fails: O4
; An Exit leaves its Block, and code after an Exit never runs. The check inside the block runs only
; when x <= 0 and the first choice is taken.
(Unit control linear
  [(VarDecl x int) (VarDecl y int)]
  [(Block done
     [(Branch (BinOp > (Var x) (Int 0))
        [(Assign y (Int 1)) (Exit done)]
        [])
      (Choice
        [(Assign y (Int 2))]
        [(Assign y (Int 3)) (Exit done) (Assign y (Int 4))])
      (Check 1 (BinOp and (BinOp <= (Var x) (Int 0)) (BinOp == (Var y) (Int 2))))])
   (Check 2 (BinOp and (BinOp >= (Var y) (Int 1)) (BinOp <= (Var y) (Int 3))))
   (Check 3 (BinOp != (Var y) (Int 4)))
   (Check 4 (BinOp == (Var y) (Int 2)))])

(obligation 1 :kind assert :node 0)
(obligation 2 :kind assert :node 0)
(obligation 3 :kind assert :node 0)
(obligation 4 :kind assert :node 0)
