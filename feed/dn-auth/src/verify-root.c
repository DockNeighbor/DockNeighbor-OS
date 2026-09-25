/*
 * verify-root: is the password on stdin root's password?
 *
 *   printf '%s\n' "$password" | /usr/libexec/dn-auth/verify-root
 *   exit 0 it is | 1 it is not | 2 could not tell (no shadow entry, unreadable, bad input)
 *
 * The password arrives on stdin, never argv (argv is visible to every process). One trailing newline is
 * stripped; nothing else is. A root with NO password (an empty hash) matches only the empty password. A locked
 * entry ("!" or "*" prefix) matches nothing.
 */
#define _DEFAULT_SOURCE
#include <crypt.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define MAX_PW 128
#define SHADOW "/etc/shadow"

/* Compare without an early exit, so the time taken says nothing about where the strings differ. */
static int same(const char *a, const char *b)
{
	size_t la = strlen(a), lb = strlen(b), i;
	unsigned char d = la != lb;
	for (i = 0; i < la && i < lb; i++)
		d |= (unsigned char)a[i] ^ (unsigned char)b[i];
	return d == 0;
}

int main(void)
{
	char pw[MAX_PW + 2], line[1024], *hash, *end, *got;
	size_t n;
	FILE *f;
	int rc = 2;

	n = fread(pw, 1, sizeof(pw) - 1, stdin);
	if (ferror(stdin))
		return 2;
	pw[n] = '\0';
	if (n > 0 && pw[n - 1] == '\n')
		pw[--n] = '\0';
	if (n > MAX_PW || strlen(pw) != n)	/* too long, or a NUL inside */
		goto out;

	f = fopen(SHADOW, "r");
	if (!f)
		goto out;
	while (fgets(line, sizeof(line), f)) {
		if (strncmp(line, "root:", 5) != 0)
			continue;
		hash = line + 5;
		end = strchr(hash, ':');
		if (!end)
			break;
		*end = '\0';
		if (hash[0] == '\0')
			rc = n == 0 ? 0 : 1;
		else if (hash[0] == '!' || hash[0] == '*')
			rc = 1;
		else {
			got = crypt(pw, hash);
			rc = got && got[0] != '*' && same(got, hash) ? 0 : 1;
		}
		break;
	}
	fclose(f);
	explicit_bzero(line, sizeof(line));
out:
	explicit_bzero(pw, sizeof(pw));
	return rc;
}
