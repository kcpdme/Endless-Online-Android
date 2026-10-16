// Native password-hash administration and truncation regression check.
// No passwords are accepted through argv or environment variables.
#include "hash.hpp"
#include <algorithm>
#include <iostream>
#include <string>

int main(int argc, char** argv)
{
    if (argc != 2) return 2;
    const std::string mode(argv[1]);
    if (mode == "--self-test") {
        const std::string prefix(80, 's');
        BcryptHasher legacy(4);
        BcryptSha256Hasher fixed(4);
        auto legacyHash = legacy.hash(prefix + "correct-password");
        auto fixedHash = fixed.hash(prefix + "correct-password");
        if (!legacy.check(prefix + "wrong-password", legacyHash)
            || !fixed.check(prefix + "correct-password", fixedHash)
            || fixed.check(prefix + "wrong-password", fixedHash)
            || fixed.check(prefix + "correct-password-suffix", fixedHash)) return 1;
        std::cout << "PASS: long salt/username cannot truncate the password in version 3\n";
        return 0;
    }
    if (mode != "--hash") return 2;
    std::string input;
    if (!std::getline(std::cin, input) || input.empty()) return 2;
    std::cout << BcryptSha256Hasher(12).hash(input) << '\n';
    std::fill(input.begin(), input.end(), '\0');
}
