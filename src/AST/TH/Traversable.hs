{-# LANGUAGE TemplateHaskellQuotes #-}

-- | Generate 'KTraversable' and related instances via @TemplateHaskell@

module AST.TH.Traversable
    ( makeKTraversable
    , makeKTraversableAndFoldable
    , makeKTraversableAndBases
    , makeKTraversableApplyAndBases
    ) where

import           AST.Class.Traversable
import           AST.TH.Apply (makeKApplicativeBases)
import           AST.TH.Foldable (makeKFoldable)
import           AST.TH.Functor (makeKFunctor)
import           AST.TH.Internal.Utils
import           AST.TH.Nodes (makeKNodes)
import           Control.Lens.Operators
import           Language.Haskell.TH

import           Prelude.Compat

-- | Generate 'KTraversable' and 'AST.Class.Apply.KApply' instances along with all of their base classes:
-- 'AST.Class.Foldable.KFoldable', 'AST.Class.Functor.KFunctor',
-- 'AST.Class.Pointed.KPointed', and 'AST.Class.Nodes.KNodes'.
makeKTraversableApplyAndBases :: Name -> DecsQ
makeKTraversableApplyAndBases x =
    sequenceA
    [ makeKApplicativeBases x
    , makeKTraversableAndFoldable x
    ] <&> concat

-- | Generate a 'KTraversable' instance along with the instance of its base classes:
-- 'AST.Class.Foldable.KFoldable', 'AST.Class.Functor.KFunctor', and 'AST.Class.Nodes.KNodes'.
makeKTraversableAndBases :: Name -> DecsQ
makeKTraversableAndBases x =
    sequenceA
    [ makeKNodes x
    , makeKFunctor x
    , makeKTraversableAndFoldable x
    ] <&> concat

-- | Generate 'KTraversable' and 'AST.Class.Foldable.KFoldable' instances
makeKTraversableAndFoldable :: Name -> DecsQ
makeKTraversableAndFoldable x =
    sequenceA
    [ makeKFoldable x
    , makeKTraversable x
    ] <&> concat

-- | Generate a 'KTraversable' instance
makeKTraversable :: Name -> DecsQ
makeKTraversable typeName = makeTypeInfo typeName >>= makeKTraversableForType

makeKTraversableForType :: TypeInfo -> DecsQ
makeKTraversableForType info =
    instanceD (simplifyContext (makeContext info)) (appT (conT ''KTraversable) (pure (tiInstance info)))
    [ InlineP 'sequenceK Inline FunLike AllPhases & PragmaD & pure
    , funD 'sequenceK (tiConstructors info <&> pure . uncurry makeCons)
    ]
    <&> (:[])

makeContext :: TypeInfo -> [Pred]
makeContext info =
    tiConstructors info >>= snd >>= ctxForPat
    where
        ctxForPat (InContainer t pat) = (ConT ''Traversable `AppT` t) : ctxForPat pat
        ctxForPat (Embed t) = [ConT ''KTraversable `AppT` t]
        ctxForPat _ = []

makeCons ::
    Name -> [CtrTypePattern] -> Clause
makeCons cName cFields =
    Clause [consPat cName consVars] body []
    where
        body =
            consVars <&> f
            & applicativeStyle (ConE cName)
            & NormalB
        consVars = makeConstructorVars "x" cFields
        f (pat, name) = bodyForPat pat `AppE` VarE name
        bodyForPat Node{} = VarE 'runContainedK
        bodyForPat Embed{} = VarE 'sequenceK
        bodyForPat (InContainer _ pat) = VarE 'traverse `AppE` bodyForPat pat
        bodyForPat PlainData{} = VarE 'pure
