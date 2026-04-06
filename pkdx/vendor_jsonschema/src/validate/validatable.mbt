///|
pub trait Validatable {
  validate(
    Self,
    Json,
    resolver~ : Resolver,
    json_path~ : @types.JsonPointer,
    schema_path~ : @types.JsonPointer,
  ) -> Array[ValidationError]
}
