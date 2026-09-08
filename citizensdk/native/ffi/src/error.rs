use std::cell::RefCell;

use citizen_sdk_engine::EngineError;

use crate::abi::CitizenSdkErrorCode;

pub type FfiResult<T> = Result<T, FfiError>;

thread_local! {
    static LAST_ERROR: RefCell<String> = const { RefCell::new(String::new()) };
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FfiError {
    pub code: CitizenSdkErrorCode,
    pub message: String,
}

impl FfiError {
    pub fn new(code: CitizenSdkErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new(CitizenSdkErrorCode::InvalidArgument, message)
    }

    pub fn internal(message: impl Into<String>) -> Self {
        Self::new(CitizenSdkErrorCode::Internal, message)
    }
}

pub fn set_last_error(error: &FfiError) {
    LAST_ERROR.with(|slot| {
        *slot.borrow_mut() = error.message.clone();
    });
}

pub fn clear_last_error() {
    LAST_ERROR.with(|slot| slot.borrow_mut().clear());
}

pub fn last_error() -> String {
    LAST_ERROR.with(|slot| slot.borrow().clone())
}

impl From<EngineError> for FfiError {
    fn from(error: EngineError) -> Self {
        match error {
            EngineError::Contract(contract) => Self::from(contract),
            other => {
                let code = match &other {
                    EngineError::InvalidMetadata(_) | EngineError::InvalidEvents(_) => {
                        CitizenSdkErrorCode::Decode
                    }
                    EngineError::BlockContextMismatch(_) => CitizenSdkErrorCode::Integrity,
                    EngineError::CapabilityUnavailable(_) => CitizenSdkErrorCode::NotReady,
                    EngineError::Cancelled => CitizenSdkErrorCode::Cancelled,
                    EngineError::Contract(_) => unreachable!("handled above"),
                    EngineError::StatePoisoned => CitizenSdkErrorCode::Internal,
                };
                Self::new(code, other.to_string())
            }
        }
    }
}

impl From<citizen_sdk_contracts::ContractError> for FfiError {
    fn from(error: citizen_sdk_contracts::ContractError) -> Self {
        use citizen_sdk_contracts::ContractErrorCode as Contract;
        let code = match error.code() {
            Contract::InvalidArgument => CitizenSdkErrorCode::InvalidArgument,
            Contract::InvalidState => CitizenSdkErrorCode::InvalidState,
            Contract::Unsupported => CitizenSdkErrorCode::Unsupported,
            Contract::Unavailable => CitizenSdkErrorCode::Unavailable,
            Contract::NotReady => CitizenSdkErrorCode::NotReady,
            Contract::NotFound => CitizenSdkErrorCode::NotFound,
            Contract::Conflict => CitizenSdkErrorCode::Conflict,
            Contract::Integrity => CitizenSdkErrorCode::Integrity,
            Contract::AuthenticationCancelled => CitizenSdkErrorCode::AuthenticationCancelled,
            Contract::AuthenticationRequired => CitizenSdkErrorCode::AuthenticationRequired,
            Contract::KeyInvalidated => CitizenSdkErrorCode::KeyInvalidated,
            Contract::PermissionDenied => CitizenSdkErrorCode::PermissionDenied,
            Contract::Storage => CitizenSdkErrorCode::Storage,
            Contract::Network => CitizenSdkErrorCode::Network,
            Contract::Decode => CitizenSdkErrorCode::Decode,
            Contract::Timeout => CitizenSdkErrorCode::Timeout,
            Contract::Internal => CitizenSdkErrorCode::Internal,
        };
        Self::new(code, error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use citizen_sdk_contracts::{ContractError, ContractErrorCode};
    use citizen_sdk_engine::EngineError;

    use super::FfiError;
    use crate::abi::CitizenSdkErrorCode;

    #[test]
    fn every_typed_contract_code_survives_engine_and_abi_mapping() {
        let cases = [
            (
                ContractErrorCode::InvalidArgument,
                CitizenSdkErrorCode::InvalidArgument,
            ),
            (
                ContractErrorCode::InvalidState,
                CitizenSdkErrorCode::InvalidState,
            ),
            (
                ContractErrorCode::Unsupported,
                CitizenSdkErrorCode::Unsupported,
            ),
            (
                ContractErrorCode::Unavailable,
                CitizenSdkErrorCode::Unavailable,
            ),
            (ContractErrorCode::NotReady, CitizenSdkErrorCode::NotReady),
            (ContractErrorCode::NotFound, CitizenSdkErrorCode::NotFound),
            (ContractErrorCode::Conflict, CitizenSdkErrorCode::Conflict),
            (ContractErrorCode::Integrity, CitizenSdkErrorCode::Integrity),
            (
                ContractErrorCode::AuthenticationCancelled,
                CitizenSdkErrorCode::AuthenticationCancelled,
            ),
            (
                ContractErrorCode::AuthenticationRequired,
                CitizenSdkErrorCode::AuthenticationRequired,
            ),
            (
                ContractErrorCode::KeyInvalidated,
                CitizenSdkErrorCode::KeyInvalidated,
            ),
            (
                ContractErrorCode::PermissionDenied,
                CitizenSdkErrorCode::PermissionDenied,
            ),
            (ContractErrorCode::Storage, CitizenSdkErrorCode::Storage),
            (ContractErrorCode::Network, CitizenSdkErrorCode::Network),
            (ContractErrorCode::Decode, CitizenSdkErrorCode::Decode),
            (ContractErrorCode::Timeout, CitizenSdkErrorCode::Timeout),
            (ContractErrorCode::Internal, CitizenSdkErrorCode::Internal),
        ];

        for (contract, expected) in cases {
            let engine = EngineError::from(ContractError::new(contract, "typed failure"));
            let ffi = FfiError::from(engine);
            assert_eq!(ffi.code, expected, "contract code {contract:?}");
            assert!(ffi.message.contains(contract.as_str()));
        }
    }
}
