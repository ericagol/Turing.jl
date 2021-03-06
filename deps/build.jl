using BinaryProvider # requires BinaryProvider 0.3.0 or later

# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))
products = [
    LibraryProduct(prefix, String["libtask"], :libtask),
]

# Download binaries from hosted location
bin_prefix = "https://github.com/hessammehr/LibtaskBuilder2/releases/download/0.1.12"

# Listing of files generated by BinaryBuilder:
download_info = Dict(
    BinaryProvider.Linux(:aarch64, :glibc, :blank_abi) => ("$bin_prefix/libtask.aarch64-linux-gnu.tar.gz", "d2ccc114b3ab606493a8a270e2844b05a52115461370fdc6e668e6b310f5e7a3"),
    BinaryProvider.Linux(:armv7l, :glibc, :eabihf) => ("$bin_prefix/libtask.arm-linux-gnueabihf.tar.gz", "0e1545529a87115a33f9c5b2cdf51e116dfa1016657d6bd877ac6e987a50cdef"),
    BinaryProvider.Linux(:i686, :glibc, :blank_abi) => ("$bin_prefix/libtask.i686-linux-gnu.tar.gz", "620b606954f526ba0bdc20786c65e0095e0df8d26c2e906cd0e04319a2c8a3b2"),
    BinaryProvider.Windows(:i686, :blank_libc, :blank_abi) => ("$bin_prefix/libtask.i686-w64-mingw32.tar.gz", "7595ecc2d5f2fc0be18f69d07a4c0d4a2e7f1bceb5495a333c5b3c5853f0b7a9"),
    BinaryProvider.Linux(:powerpc64le, :glibc, :blank_abi) => ("$bin_prefix/libtask.powerpc64le-linux-gnu.tar.gz", "cb269617e977a8a576c18fa40e31a0080a1d9b365dd2330746345cfedb3f81a3"),
    BinaryProvider.MacOS(:x86_64, :blank_libc, :blank_abi) => ("$bin_prefix/libtask.x86_64-apple-darwin14.tar.gz", "bbc4d6b2d4ddc83dd842d633da36faaeb459163af1461e4fe2237821c3f8dbdd"),
    BinaryProvider.Linux(:x86_64, :glibc, :blank_abi) => ("$bin_prefix/libtask.x86_64-linux-gnu.tar.gz", "e044bace4fbc88844af3a7eb2346b8824aa4d1c5853977c0a35e54296d8a9389"),
    BinaryProvider.Windows(:x86_64, :blank_libc, :blank_abi) => ("$bin_prefix/libtask.x86_64-w64-mingw32.tar.gz", "2158e66eff878641f7a39cdbf20b9b41a007f1dc2242bb3655dccb2e2ac65830"),
)

# Install unsatisfied or updated dependencies:
unsatisfied = any(!satisfied(p; verbose=verbose) for p in products)
if haskey(download_info, platform_key())
    url, tarball_hash = download_info[platform_key()]
    if unsatisfied || !isinstalled(url, tarball_hash; prefix=prefix)
        # Download and install binaries
        install(url, tarball_hash; prefix=prefix, force=true, verbose=verbose)
    end
elseif unsatisfied
    # If we don't have a BinaryProvider-compatible .tar.gz to download, complain.
    # Alternatively, you could attempt to install from a separate provider,
    # build from source or something more even more ambitious here.
    error("Your platform $(triplet(platform_key())) is not supported by this package!")
end

# Write out a deps.jl file that will contain mappings for our products
write_deps_file(joinpath(@__DIR__, "deps.jl"), products)
