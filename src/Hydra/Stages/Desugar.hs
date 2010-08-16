{-# LANGUAGE TemplateHaskell #-}


module Hydra.Stages.Desugar (desugar) where

import Hydra.BNFC.AbsHydra
import Hydra.Utils.Impossible (impossible)

desugar :: SigRel -> SigRel
desugar = desugarFlowSigRel . desugarConnectSigRel

desugarConnectSigRel :: SigRel -> SigRel
desugarConnectSigRel sr = case sr of
  SigRel pat1 eqs1 ->  SigRel pat1 (concatMap desugarConnectEquation eqs1)

desugarConnectEquation :: Equation -> [Equation]
desugarConnectEquation eq = case eq of
  EquationSigRelApp hsExpr1 e1 -> [EquationSigRelApp  hsExpr1 e1]

  EquationEqual (ExprTuple es1) (ExprTuple es2) ->
    if length es1 == length es2
      then concatMap desugarConnectEquation (zipWith EquationEqual es1 es2)
      else error ("Types do not agree in equation: " ++ show eq)
  EquationEqual _ _ -> [eq]

  EquationInit (ExprTuple es1) (ExprTuple es2) ->
    if length es1 == length es2
      then concatMap desugarConnectEquation (zipWith EquationInit es1 es2)
      else error ("Types do not agree in equation: " ++ show eq)
  EquationInit _ _ -> [eq]

  EquationReinit (ExprTuple es1) (ExprTuple es2) ->
    if length es1 == length es2
      then concatMap desugarConnectEquation (zipWith EquationReinit es1 es2)
      else error ("Types do not agree in equation: " ++ show eq)
  EquationReinit _ _ -> [eq]

  EquationLocal _ [] -> [eq]
  EquationLocal li1 (li2 : lis) -> (EquationLocal li1 []) : desugarConnectEquation (EquationLocal li2 lis)

  EquationConnect li1 li2 lis ->
    let vs = map ExprVar (li1 : li2 : lis)
    in  zipWith EquationEqual vs (tail vs)
  EquationConnectFlow li1 li2 lis ->
    let vs = map ExprVar (li1 : li2 : lis)
    in  [EquationEqual  (foldr1 (\e1 e2 -> ExprAdd e1 e2) vs) (ExprReal 0.0)]

  EquationMonitor _ -> [eq]

desugarFlowSigRel :: SigRel -> SigRel
desugarFlowSigRel (SigRel pat1 eqs1) =
  let flowVars = desugarFlowFindPattern pat1
      pat2 = desugarFlowForgetPattern pat1
      eqs2 = foldr (\s eqs -> desugarFlowEquations s eqs) eqs1 flowVars
  in  SigRel pat2 eqs2 

desugarFlowFindPattern :: Pattern -> [String]
desugarFlowFindPattern pat = case pat of
  PatternWild -> []
  PatternName PatternNameQualEmpty _ -> []
  PatternName PatternNameQualFlow  (LIdent s1) -> [s1]
  PatternTuple pats1 -> concatMap desugarFlowFindPattern pats1

desugarFlowForgetPattern :: Pattern -> Pattern
desugarFlowForgetPattern pat = case pat of
  PatternWild -> pat
  PatternName PatternNameQualEmpty _ -> pat
  PatternName PatternNameQualFlow  li1 -> PatternName PatternNameQualEmpty li1
  PatternTuple pats1 -> PatternTuple (map desugarFlowForgetPattern pats1)

desugarFlowEquations :: String -> [Equation] -> [Equation]
desugarFlowEquations _ [] = []
desugarFlowEquations s (eq : eqs) =
  let go :: Expr -> Expr
      go = desugarFlowExpr s
  in  case eq of
        EquationSigRelApp hsExpr1 e1 -> (EquationSigRelApp hsExpr1 (go e1)) : desugarFlowEquations s eqs
        EquationEqual e1 e2          -> (EquationEqual (go e1) (go e2))     : desugarFlowEquations s eqs
        EquationInit e1 e2           -> (EquationInit (go e1) (go e2))      : desugarFlowEquations s eqs
        EquationReinit e1 e2         -> (EquationReinit (go e1) (go e2))    : desugarFlowEquations s eqs
        EquationLocal (LIdent s1) [] -> if s1 == s then (eq : eqs) else  eq : desugarFlowEquations s eqs
        EquationLocal _ _ -> $impossible
        EquationConnect _ _ _ -> $impossible
        EquationConnectFlow _ _ _ -> $impossible
        EquationMonitor _ -> eq : desugarFlowEquations s eqs

desugarFlowExpr :: String -> Expr -> Expr
desugarFlowExpr s expr = go expr
  where
  go :: Expr -> Expr
  go e = case e of
    ExprVar (LIdent s1) -> if s1 == s then ExprNeg e else e

    ExprAdd e1 e2 -> ExprAdd (go e1) (go e2)
    ExprSub e1 e2 -> ExprSub (go e1) (go e2)
    ExprDiv e1 e2 -> ExprDiv (go e1) (go e2)
    ExprMul e1 e2 -> ExprMul (go e1) (go e2)
    ExprPow e1 e2 -> ExprPow (go e1) (go e2)
    ExprApp v1 e1 -> ExprApp v1 (go e1)
    ExprNeg e1    -> ExprNeg (go e1)

    ExprTuple es1 -> ExprTuple (map go es1)

    ExprAnti _ -> e
    ExprInt  _ -> e
    ExprReal _ -> e
