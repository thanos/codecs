%{
  configs: [
    %{
      name: "ex_codecs",
      strict: true,
      color: true,
      checks: [
        {Credo.Check.Consistency.TabsOrSpaces, []},
        {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
        {Credo.Check.Consistency.ModuleEqualsNamespaced, []},
        {Credo.Check.Consistency.ParameterPatternMatching, []},
        {Credo.Check.Consistency.LineEndings, []},

        {Credo.Check.Readability.ModuleDoc, []},
        {Credo.Check.Readability.ModuleNames, []},
        {Credo.Check.Readability.FunctionNames, []},
        {Credo.Check.Readability.PredicateFunctionNames, []},
        {Credo.Check.Readability.Specs, []},
        {Credo.Check.Readability.SinglePipe, []},
        {Credo.Check.Readability.LargeNumbers, []},
        {Credo.Check.Readability.StringSigils, []},
        {Credo.Check.Readability.AliasAs, []},
        {Credo.Check.Readability.BlockPipe, []},
        {Credo.Check.Readability.SeparateAliasRequire, []},
        {Credo.Check.Readability.TrailingWhiteSpace, []},
        {Credo.Check.Readability.WithSingleClause, []},
        {Credo.Check.Readability.AliasOrder, []},

        {Credo.Check.Refactor.PipeChainStart, [excluded_previous_pipe_step_types: [:atom, :string]]},
        {Credo.Check.Refactor.FilterCount, []},
        {Credo.Check.Refactor.MapJoin, []},
        {Credo.Check.Refactor.MapMap, []},
        {Credo.Check.Refactor.NegatedIsNil, []},
        {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
        {Credo.Check.Refactor.PerceivedComplexity, [max_complexity: 10]},
        {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 8]},
        {Credo.Check.Refactor.DoubleBooleanNegation, []},
        {Credo.Check.Refactor.PassAsyncInTestCases, []},

        {Credo.Check.Warning.IoInspect, []},
        {Credo.Check.Warning.IExPry, []},
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
        {Credo.Check.Warning.UnusedEnumOperation, []},
        {Credo.Check.Warning.MapGetUnsafePass, []},
        {Credo.Check.Warning.LazyLogging, []},
        {Credo.Check.Warning.OperationOnSameValues, []},
        {Credo.Check.Warning.BoolOperationOnSameValues, []},
        {Credo.Check.Warning.MissedMetadataKey, []}
      ]
    }
  ]
}