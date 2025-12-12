"use strict";
/*
 * ATTENTION: An "eval-source-map" devtool has been used.
 * This devtool is neither made for production nor for readable output files.
 * It uses "eval()" calls to create a separate source file with attached SourceMaps in the browser devtools.
 * If you are trying to read the output file, select a different devtool (https://webpack.js.org/configuration/devtool/)
 * or disable the default devtool with "devtool: false".
 * If you are looking for production-ready output files, see mode: "production" (https://webpack.js.org/configuration/mode/).
 */
exports.id = "vendor-chunks/is-retry-allowed";
exports.ids = ["vendor-chunks/is-retry-allowed"];
exports.modules = {

/***/ "(ssr)/./node_modules/is-retry-allowed/index.js":
/*!************************************************!*\
  !*** ./node_modules/is-retry-allowed/index.js ***!
  \************************************************/
/***/ ((module) => {

eval("\nconst denyList = new Set([\n    \"ENOTFOUND\",\n    \"ENETUNREACH\",\n    // SSL errors from https://github.com/nodejs/node/blob/fc8e3e2cdc521978351de257030db0076d79e0ab/src/crypto/crypto_common.cc#L301-L328\n    \"UNABLE_TO_GET_ISSUER_CERT\",\n    \"UNABLE_TO_GET_CRL\",\n    \"UNABLE_TO_DECRYPT_CERT_SIGNATURE\",\n    \"UNABLE_TO_DECRYPT_CRL_SIGNATURE\",\n    \"UNABLE_TO_DECODE_ISSUER_PUBLIC_KEY\",\n    \"CERT_SIGNATURE_FAILURE\",\n    \"CRL_SIGNATURE_FAILURE\",\n    \"CERT_NOT_YET_VALID\",\n    \"CERT_HAS_EXPIRED\",\n    \"CRL_NOT_YET_VALID\",\n    \"CRL_HAS_EXPIRED\",\n    \"ERROR_IN_CERT_NOT_BEFORE_FIELD\",\n    \"ERROR_IN_CERT_NOT_AFTER_FIELD\",\n    \"ERROR_IN_CRL_LAST_UPDATE_FIELD\",\n    \"ERROR_IN_CRL_NEXT_UPDATE_FIELD\",\n    \"OUT_OF_MEM\",\n    \"DEPTH_ZERO_SELF_SIGNED_CERT\",\n    \"SELF_SIGNED_CERT_IN_CHAIN\",\n    \"UNABLE_TO_GET_ISSUER_CERT_LOCALLY\",\n    \"UNABLE_TO_VERIFY_LEAF_SIGNATURE\",\n    \"CERT_CHAIN_TOO_LONG\",\n    \"CERT_REVOKED\",\n    \"INVALID_CA\",\n    \"PATH_LENGTH_EXCEEDED\",\n    \"INVALID_PURPOSE\",\n    \"CERT_UNTRUSTED\",\n    \"CERT_REJECTED\",\n    \"HOSTNAME_MISMATCH\"\n]);\n// TODO: Use `error?.code` when targeting Node.js 14\nmodule.exports = (error)=>!denyList.has(error && error.code);\n//# sourceURL=[module]\n//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiKHNzcikvLi9ub2RlX21vZHVsZXMvaXMtcmV0cnktYWxsb3dlZC9pbmRleC5qcyIsIm1hcHBpbmdzIjoiQUFBQTtBQUVBLE1BQU1BLFdBQVcsSUFBSUMsSUFBSTtJQUN4QjtJQUNBO0lBRUEscUlBQXFJO0lBQ3JJO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0lBQ0E7SUFDQTtJQUNBO0NBQ0E7QUFFRCxvREFBb0Q7QUFDcERDLE9BQU9DLE9BQU8sR0FBR0MsQ0FBQUEsUUFBUyxDQUFDSixTQUFTSyxHQUFHLENBQUNELFNBQVNBLE1BQU1FLElBQUkiLCJzb3VyY2VzIjpbIndlYnBhY2s6Ly9haW1ob29rLWZyb250ZW5kLy4vbm9kZV9tb2R1bGVzL2lzLXJldHJ5LWFsbG93ZWQvaW5kZXguanM/Y2FlNSJdLCJzb3VyY2VzQ29udGVudCI6WyIndXNlIHN0cmljdCc7XG5cbmNvbnN0IGRlbnlMaXN0ID0gbmV3IFNldChbXG5cdCdFTk9URk9VTkQnLFxuXHQnRU5FVFVOUkVBQ0gnLFxuXG5cdC8vIFNTTCBlcnJvcnMgZnJvbSBodHRwczovL2dpdGh1Yi5jb20vbm9kZWpzL25vZGUvYmxvYi9mYzhlM2UyY2RjNTIxOTc4MzUxZGUyNTcwMzBkYjAwNzZkNzllMGFiL3NyYy9jcnlwdG8vY3J5cHRvX2NvbW1vbi5jYyNMMzAxLUwzMjhcblx0J1VOQUJMRV9UT19HRVRfSVNTVUVSX0NFUlQnLFxuXHQnVU5BQkxFX1RPX0dFVF9DUkwnLFxuXHQnVU5BQkxFX1RPX0RFQ1JZUFRfQ0VSVF9TSUdOQVRVUkUnLFxuXHQnVU5BQkxFX1RPX0RFQ1JZUFRfQ1JMX1NJR05BVFVSRScsXG5cdCdVTkFCTEVfVE9fREVDT0RFX0lTU1VFUl9QVUJMSUNfS0VZJyxcblx0J0NFUlRfU0lHTkFUVVJFX0ZBSUxVUkUnLFxuXHQnQ1JMX1NJR05BVFVSRV9GQUlMVVJFJyxcblx0J0NFUlRfTk9UX1lFVF9WQUxJRCcsXG5cdCdDRVJUX0hBU19FWFBJUkVEJyxcblx0J0NSTF9OT1RfWUVUX1ZBTElEJyxcblx0J0NSTF9IQVNfRVhQSVJFRCcsXG5cdCdFUlJPUl9JTl9DRVJUX05PVF9CRUZPUkVfRklFTEQnLFxuXHQnRVJST1JfSU5fQ0VSVF9OT1RfQUZURVJfRklFTEQnLFxuXHQnRVJST1JfSU5fQ1JMX0xBU1RfVVBEQVRFX0ZJRUxEJyxcblx0J0VSUk9SX0lOX0NSTF9ORVhUX1VQREFURV9GSUVMRCcsXG5cdCdPVVRfT0ZfTUVNJyxcblx0J0RFUFRIX1pFUk9fU0VMRl9TSUdORURfQ0VSVCcsXG5cdCdTRUxGX1NJR05FRF9DRVJUX0lOX0NIQUlOJyxcblx0J1VOQUJMRV9UT19HRVRfSVNTVUVSX0NFUlRfTE9DQUxMWScsXG5cdCdVTkFCTEVfVE9fVkVSSUZZX0xFQUZfU0lHTkFUVVJFJyxcblx0J0NFUlRfQ0hBSU5fVE9PX0xPTkcnLFxuXHQnQ0VSVF9SRVZPS0VEJyxcblx0J0lOVkFMSURfQ0EnLFxuXHQnUEFUSF9MRU5HVEhfRVhDRUVERUQnLFxuXHQnSU5WQUxJRF9QVVJQT1NFJyxcblx0J0NFUlRfVU5UUlVTVEVEJyxcblx0J0NFUlRfUkVKRUNURUQnLFxuXHQnSE9TVE5BTUVfTUlTTUFUQ0gnXG5dKTtcblxuLy8gVE9ETzogVXNlIGBlcnJvcj8uY29kZWAgd2hlbiB0YXJnZXRpbmcgTm9kZS5qcyAxNFxubW9kdWxlLmV4cG9ydHMgPSBlcnJvciA9PiAhZGVueUxpc3QuaGFzKGVycm9yICYmIGVycm9yLmNvZGUpO1xuIl0sIm5hbWVzIjpbImRlbnlMaXN0IiwiU2V0IiwibW9kdWxlIiwiZXhwb3J0cyIsImVycm9yIiwiaGFzIiwiY29kZSJdLCJzb3VyY2VSb290IjoiIn0=\n//# sourceURL=webpack-internal:///(ssr)/./node_modules/is-retry-allowed/index.js\n");

/***/ })

};
;