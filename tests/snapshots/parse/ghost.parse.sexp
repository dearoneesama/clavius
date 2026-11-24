(Block
  [(ClvSpec
     [(LocalFunction
        (Binder same)
        (Function
          [(ClvParam n false (ClvTypeName Nat)) (ClvReturn nil (ClvTypeName Nat))]
          [(Binder n)]
          false
          (Block [(Return [(Id n)])])))])
   (ClvRegion
     [(Local [(Literal number 1)] [(Binder x)])
      (ClvGhost [(Local [(Literal number 0)] [(Binder seen)])])
      (ClvGhost [(Set [(Id seen)] [(BinOp add (Id seen) (Id x))])])
      (ClvGhost
        [(Local [(BinOp add (Id seen) (Id seen))] [(Binder twice)])
         (Set [(Id seen) (Id twice)] [(Id twice) (Id seen)])])
      (ClvAssert (BinOp eq (Id seen) (Literal number 2)))
      (ClvProof true
        [(Local [(Id x)] [(Binder y)])
         (If [(IfArm (BinOp gt (Id y) (Literal number 0)) (Block []))] nil)])
      (ClvLemma
        [(Local [] [(Binder f) (Binder g)])
         (Set
           [(Id f)]
           [(Function [(ClvParam n false (ClvTypeName Nat))] [(Binder n)] false (Block []))])
         (Set
           [(Id g)]
           [(Function [(ClvParam n false (ClvTypeName Nat))] [(Binder n)] false (Block []))])])
      (ClvProof false [(Call (Id f) nil [(Id x)])])])])
