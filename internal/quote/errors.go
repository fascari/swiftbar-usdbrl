package quote

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
)

const (
	Other ErrorKind = iota + 1
	HTTPError
	NoConnection
	TLS
	Invalid
)

type (
	ErrorKind uint8

	FetchError struct {
		Kind   ErrorKind
		Status int
	}
)

func (e FetchError) Error() string {
	return fmt.Sprintf("fetch failed (kind %d, HTTP status %d)", e.Kind, e.Status)
}

func responseError(kind ErrorKind, status int) FetchError {
	return FetchError{
		Kind:   kind,
		Status: status,
	}
}

func requestError(err error) FetchError {
	_, invalidCertificate := errors.AsType[*tls.CertificateVerificationError](err)
	_, recordError := errors.AsType[tls.RecordHeaderError](err)
	_, alert := errors.AsType[tls.AlertError](err)
	cause := err
	if urlErr, ok := errors.AsType[*url.Error](err); ok {
		cause = urlErr.Err
	}
	isTLS := invalidCertificate || recordError || alert ||
		errors.Is(err, http.ErrSchemeMismatch) || strings.HasPrefix(cause.Error(), "tls:")
	if isTLS {
		return FetchError{Kind: TLS}
	}
	netErr, isNetworkError := errors.AsType[net.Error](cause)
	opErr, isOperationError := errors.AsType[*net.OpError](cause)
	isTimeout := errors.Is(err, context.DeadlineExceeded) || (isNetworkError && netErr.Timeout())
	if isTimeout || (isOperationError && opErr.Op == "dial") {
		return FetchError{Kind: NoConnection}
	}
	if _, ok := errors.AsType[*net.DNSError](cause); ok {
		return FetchError{Kind: NoConnection}
	}
	return FetchError{Kind: Other}
}
